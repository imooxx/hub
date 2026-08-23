#!/usr/bin/env bash
#
# GOST V3 管理脚本 V2.1
# 目标：
#   - 普通 TCP / UDP 本地端口转发
#   - Relay TCP 客户端
#   - Relay over TLS / WS / WSS 服务端
#   - Relay over TLS / WS / WSS 客户端
#   - TLS 服务端证书、CA、SNI
#   - WS/WSS Host、Path
#   - 原子生成 + GOST 原生解析 + 失败不覆盖旧配置
#
# GOST 配置文件：/etc/gost/config.yaml
# 任务数据库：  /etc/gost/.registry.db
#
# registry:
# name|type|listen_port|target_host|target_port|transport|secure|sni|ws_path|ws_host|cert|key|ca
#
set -u
umask 022

CONFIG_DIR="/etc/gost"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
TMP_CONFIG="$CONFIG_DIR/config.tmp.yaml"
BACKUP_CONFIG="$CONFIG_DIR/config.yaml.bak"
DB_FILE="$CONFIG_DIR/.registry.db"
BINARY_PATH="/usr/local/bin/gost"
SYSTEMD_FILE="/etc/systemd/system/gost.service"
GITHUB_API="https://api.github.com/repos/go-gost/gost/releases/latest"

die() { echo "❌ $*"; return 1; }
need_root() { [ "${EUID:-$(id -u)}" -eq 0 ] || { echo "❌ 请使用 root 运行。"; exit 1; }; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

ensure_tools() {
    local x missing=()
    for x in curl tar awk sed grep systemctl install mktemp find; do
        command_exists "$x" || missing+=("$x")
    done
    [ "${#missing[@]}" -eq 0 ] || {
        echo "❌ 缺少：${missing[*]}"
        echo "Debian 可执行：apt update && apt install -y curl tar awk sed grep systemd coreutils findutils"
        return 1
    }
}

init_dirs() {
    mkdir -p "$CONFIG_DIR"
    touch "$DB_FILE"
    chmod 700 "$CONFIG_DIR"
    chmod 600 "$DB_FILE"
}

valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}
valid_name() { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]; }
name_exists() { awk -F'|' -v n="$1" '$1==n{f=1}END{exit !f}' "$DB_FILE"; }
port_conflict() { awk -F'|' -v p="$1" -v n="${2:-}" '$3==p&&$1!=n{f=1}END{exit !f}' "$DB_FILE"; }

target_addr() {
    local h="$1" p="$2"
    h="${h#[}"; h="${h%]}"
    if [[ "$h" == *:* ]]; then printf '[%s]:%s' "$h" "$p"
    else printf '%s:%s' "$h" "$p"; fi
}

# ---------------- GOST 版本 / 安装 ----------------

latest_version() {
    local j tag
    j="$(curl -fsSL --retry 3 --connect-timeout 10 "$GITHUB_API")" || return 1
    if command_exists jq; then
        tag="$(printf '%s' "$j" | jq -r '.tag_name // empty')"
    else
        tag="$(printf '%s' "$j" | grep -m1 '"tag_name":' |
            sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
    fi
    [ -n "$tag" ] && printf '%s' "${tag#v}"
}

arch_suffix() {
    case "$(uname -m)" in
        x86_64|amd64) echo amd64;;
        aarch64|arm64) echo arm64;;
        armv7|armv7l) echo armv7;;
        *) return 1;;
    esac
}

download_url() {
    local arch="$1" j u
    j="$(curl -fsSL --retry 3 --connect-timeout 10 "$GITHUB_API")" || return 1
    if command_exists jq; then
        u="$(printf '%s' "$j" | jq -r --arg a "$arch" '
          .assets[] | select(.name | test("linux_" + $a + "\\.tar\\.gz$")) |
          .browser_download_url' | head -n1)"
    else
        u="$(printf '%s' "$j" | grep -oE '"browser_download_url":[[:space:]]*"[^"]+linux_[^"]+\.tar\.gz"' |
          sed -E 's/.*"browser_download_url":[[:space:]]*"([^"]+)".*/\1/' |
          grep "linux_${arch}\.tar\.gz" | head -n1)"
    fi
    [ -n "$u" ] && printf '%s' "$u"
}

installed_version() {
    [ -x "$BINARY_PATH" ] || return 1
    "$BINARY_PATH" -V 2>&1 |
      sed -nE 's/.*gost[[:space:]]+v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n1
}

install_gost() {
    ensure_tools || return 1
    init_dirs
    local v a u d archive bin
    v="$(latest_version)" || { echo "❌ 无法获取 GOST 最新版本。"; return 1; }
    a="$(arch_suffix)" || { echo "❌ 不支持架构：$(uname -m)"; return 1; }
    u="$(download_url "$a")" || { echo "❌ 找不到 linux_${a} 发布包。"; return 1; }

    echo "⬇️ GOST $v / $a"
    d="$(mktemp -d /tmp/gost-v21.XXXXXX)"
    archive="$d/gost.tar.gz"

    curl -fL --retry 3 --connect-timeout 10 "$u" -o "$archive" || {
        rm -rf "$d"; echo "❌ 下载失败。"; return 1;
    }
    mkdir -p "$d/x"
    tar -xzf "$archive" -C "$d/x" || {
        rm -rf "$d"; echo "❌ 解压失败。"; return 1;
    }
    bin="$(find "$d/x" -type f -name gost | head -n1)"
    [ -n "$bin" ] || { rm -rf "$d"; echo "❌ 未找到 gost。"; return 1; }

    systemctl stop gost.service 2>/dev/null || true
    install -m 0755 "$bin" "$BINARY_PATH"
    rm -rf "$d"

    echo "✅ GOST $v 安装完成。"
    write_systemd
    [ -f "$CONFIG_FILE" ] && restart_gost
}

update_gost() {
    local cur new
    cur="$(installed_version 2>/dev/null || true)"
    new="$(latest_version 2>/dev/null || true)"
    [ -n "$new" ] || { echo "❌ 无法获取最新版本。"; return 1; }
    echo "当前：${cur:-未安装}"
    echo "最新：$new"
    [ "$cur" = "$new" ] && { echo "✨ 已是最新。"; return 0; }
    install_gost
}

# ---------------- Systemd / 安全启动 ----------------

write_systemd() {
    cat > "$SYSTEMD_FILE" <<EOF
[Unit]
Description=GOST V3 Forwarding Service
Documentation=https://gost.run/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$CONFIG_DIR
ExecStart=$BINARY_PATH -C $CONFIG_FILE
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "$SYSTEMD_FILE"
    systemctl daemon-reload
    systemctl enable gost.service >/dev/null 2>&1
}

validate_config_file() {
    local f="$1"
    [ -f "$f" ] || return 1

    # GOST 根据扩展名识别配置类型，临时文件必须以 .yaml/.yml/.json 结尾。
    case "$f" in
        *.yaml|*.yml|*.json) ;;
        *) echo "❌ 临时配置扩展名错误：$f"; return 1;;
    esac

    "$BINARY_PATH" -C "$f" -O yaml >/dev/null 2>&1
}

restart_gost() {
    [ -x "$BINARY_PATH" ] || { echo "❌ GOST 未安装。"; return 1; }
    [ -f "$CONFIG_FILE" ] || { echo "❌ 配置不存在。"; return 1; }

    echo "🔍 检查正式配置..."
    if ! validate_config_file "$CONFIG_FILE"; then
        echo "❌ 正式配置无法通过 GOST 原生解析。"
        "$BINARY_PATH" -C "$CONFIG_FILE" -O yaml 2>&1 || true
        return 1
    fi

    systemctl restart gost.service
    sleep 1
    if systemctl is-active --quiet gost.service; then
        echo "🟢 GOST Running"
        return 0
    fi

    echo "❌ GOST 启动失败："
    journalctl -u gost.service -n 40 --no-pager
    return 1
}

# ---------------- YAML 生成 ----------------

yaml_q() { printf '"%s"' "$1"; }

generate_yaml() {
    init_dirs
    cat > "$TMP_CONFIG" <<'EOF'
# GOST V3 configuration generated by gost.sh V2.1
# DO NOT EDIT MANUALLY.
services:
EOF

    local name type port host tport transport secure sni path ws_host cert key ca
    local taddr
    local need_chains=0

    while IFS='|' read -r name type port host tport transport secure sni path ws_host cert key ca; do
        [ -n "$name" ] || continue

        case "$type" in
            tcp)
                taddr="$(target_addr "$host" "$tport")"
                cat >> "$TMP_CONFIG" <<EOF
  - name: "tcp-${name}"
    addr: ":${port}"
    handler:
      type: tcp
    listener:
      type: tcp
    forwarder:
      nodes:
        - name: "target-${name}"
          addr: "${taddr}"
EOF
                ;;
            udp)
                taddr="$(target_addr "$host" "$tport")"
                cat >> "$TMP_CONFIG" <<EOF
  - name: "udp-${name}"
    addr: ":${port}"
    handler:
      type: udp
    listener:
      type: udp
    forwarder:
      nodes:
        - name: "target-${name}"
          addr: "${taddr}"
EOF
                ;;
            relay_server)
                cat >> "$TMP_CONFIG" <<EOF
  - name: "relay-server-${name}"
    addr: ":${port}"
    handler:
      type: relay
    listener:
      type: ${transport}
EOF
                if [ "$transport" = "ws" ] || [ "$transport" = "wss" ]; then
                    cat >> "$TMP_CONFIG" <<EOF
      metadata:
        path: "${path:-/ws}"
        enableCompression: false
EOF
                    [ -n "$ws_host" ] && cat >> "$TMP_CONFIG" <<EOF
        host: "${ws_host}"
EOF
                fi

                if [ "$transport" = "tls" ] || [ "$transport" = "wss" ]; then
                    if [ -n "$cert" ] || [ -n "$key" ] || [ -n "$ca" ]; then
                        cat >> "$TMP_CONFIG" <<EOF
      tls:
EOF
                        [ -n "$cert" ] && printf '        certFile: "%s"\n' "$cert" >> "$TMP_CONFIG"
                        [ -n "$key" ]  && printf '        keyFile: "%s"\n' "$key" >> "$TMP_CONFIG"
                        [ -n "$ca" ]   && printf '        caFile: "%s"\n' "$ca" >> "$TMP_CONFIG"
                    fi
                fi
                ;;
            relay_client)
                cat >> "$TMP_CONFIG" <<EOF
  - name: "relay-client-${name}"
    addr: ":${port}"
    handler:
      type: tcp
      chain: "chain-${name}"
    listener:
      type: tcp
EOF
                need_chains=1
                ;;
        esac
    done < "$DB_FILE"

    if [ "$need_chains" -eq 1 ]; then
        printf '\nchains:\n' >> "$TMP_CONFIG"

        while IFS='|' read -r name type port host tport transport secure sni path ws_host cert key ca; do
            [ "$type" = "relay_client" ] || continue
            taddr="$(target_addr "$host" "$tport")"

            cat >> "$TMP_CONFIG" <<EOF
  - name: "chain-${name}"
    hops:
      - name: "hop-${name}"
        nodes:
          - name: "node-${name}"
            addr: "${taddr}"
            connector:
              type: relay
            dialer:
              type: ${transport}
EOF

            if [ "$transport" = "tls" ] || [ "$transport" = "wss" ]; then
                if [ "$secure" = "true" ] || [ -n "$sni" ] || [ -n "$cert" ] || [ -n "$key" ] || [ -n "$ca" ]; then
                    cat >> "$TMP_CONFIG" <<EOF
              tls:
EOF
                    printf '                secure: %s\n' "${secure:-false}" >> "$TMP_CONFIG"
                    [ -n "$sni" ] && printf '                serverName: "%s"\n' "$sni" >> "$TMP_CONFIG"
                    [ -n "$cert" ] && printf '                certFile: "%s"\n' "$cert" >> "$TMP_CONFIG"
                    [ -n "$key" ] && printf '                keyFile: "%s"\n' "$key" >> "$TMP_CONFIG"
                    [ -n "$ca" ] && printf '                caFile: "%s"\n' "$ca" >> "$TMP_CONFIG"
                fi
            fi

            if [ "$transport" = "ws" ] || [ "$transport" = "wss" ]; then
                cat >> "$TMP_CONFIG" <<EOF
            dialer:
EOF
                # The previous dialer block already exists, so this branch must not
                # be used. Kept impossible by the corrected generator below.
            fi
        done < "$DB_FILE"
    fi

    # Rebuild chains cleanly because WS/WSS metadata belongs under dialer.metadata,
    # not beside dialer.
    if [ "$need_chains" -eq 1 ]; then
        # Remove the malformed chain section and regenerate it.
        sed -i '/^chains:$/,$d' "$TMP_CONFIG"
        printf '\nchains:\n' >> "$TMP_CONFIG"

        while IFS='|' read -r name type port host tport transport secure sni path ws_host cert key ca; do
            [ "$type" = "relay_client" ] || continue
            taddr="$(target_addr "$host" "$tport")"

            cat >> "$TMP_CONFIG" <<EOF
  - name: "chain-${name}"
    hops:
      - name: "hop-${name}"
        nodes:
          - name: "node-${name}"
            addr: "${taddr}"
            connector:
              type: relay
            dialer:
              type: ${transport}
EOF

            if [ "$transport" = "tls" ]; then
                cat >> "$TMP_CONFIG" <<EOF
              tls:
                secure: ${secure:-false}
EOF
                [ -n "$sni" ] && printf '                serverName: "%s"\n' "$sni" >> "$TMP_CONFIG"
                [ -n "$cert" ] && printf '                certFile: "%s"\n' "$cert" >> "$TMP_CONFIG"
                [ -n "$key" ] && printf '                keyFile: "%s"\n' "$key" >> "$TMP_CONFIG"
                [ -n "$ca" ] && printf '                caFile: "%s"\n' "$ca" >> "$TMP_CONFIG"
            elif [ "$transport" = "ws" ] || [ "$transport" = "wss" ]; then
                cat >> "$TMP_CONFIG" <<EOF
              metadata:
                path: "${path:-/ws}"
                enableCompression: false
EOF
                [ -n "$ws_host" ] && printf '                host: "%s"\n' "$ws_host" >> "$TMP_CONFIG"
            fi
        done < "$DB_FILE"
    fi

    chmod 600 "$TMP_CONFIG"
}

apply_yaml() {
    generate_yaml

    echo "🔍 使用 GOST 原生解析器检查新配置..."
    if ! validate_config_file "$TMP_CONFIG"; then
        echo "❌ 新配置未通过 GOST 配置解析。"
        echo "---- GOST 输出 ----"
        "$BINARY_PATH" -C "$TMP_CONFIG" -O yaml 2>&1 || true
        echo "-------------------"
        rm -f "$TMP_CONFIG"
        return 1
    fi

    [ -f "$CONFIG_FILE" ] && cp -a "$CONFIG_FILE" "$BACKUP_CONFIG"
    mv -f "$TMP_CONFIG" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    echo "✅ 新配置已经通过 GOST 原生解析。"
    echo "✅ 已原子替换 $CONFIG_FILE"

    if [ -x "$BINARY_PATH" ]; then
        write_systemd
        restart_gost
    fi
}

# ---------------- Registry / 任务 ----------------

list_tasks() {
    local i=1 name type port host tport transport secure sni path ws_host cert key ca
    [ -s "$DB_FILE" ] || { echo "📭 没有任务。"; return 1; }

    while IFS='|' read -r name type port host tport transport secure sni path ws_host cert key ca; do
        [ -n "$name" ] || continue
        case "$type" in
            tcp) echo "$i. [TCP]       $name :$port -> $(target_addr "$host" "$tport")";;
            udp) echo "$i. [UDP]       $name :$port -> $(target_addr "$host" "$tport")";;
            relay_server) echo "$i. [Relay服务端] $name :$port -> $transport ${path:-}";;
            relay_client) echo "$i. [Relay客户端] $name :$port -> $(target_addr "$host" "$tport") / $transport";;
        esac
        i=$((i+1))
    done < "$DB_FILE"
}

name_by_index() {
    local want="$1" i=1 name
    while IFS='|' read -r name _; do
        [ -n "$name" ] || continue
        [ "$i" -eq "$want" ] && { printf '%s' "$name"; return 0; }
        i=$((i+1))
    done < "$DB_FILE"
    return 1
}

read_transport() {
    local x
    echo "1. TLS"
    echo "2. WebSocket (WS)"
    echo "3. WebSocket over TLS (WSS)"
    read -r -p "选择传输方式: " x
    case "$x" in
        1) echo tls;;
        2) echo ws;;
        3) echo wss;;
        *) return 1;;
    esac
}

create_task() {
    init_dirs
    echo "========== 新建任务 =========="
    echo "1. TCP 本地转发"
    echo "2. UDP 本地转发"
    echo "3. Relay 服务端"
    echo "4. Relay 客户端"
    local choice name port host tport transport secure sni path ws_host cert key ca
    read -r -p "选择 (1-4): " choice
    read -r -p "任务名称: " name

    valid_name "$name" || { echo "❌ 名称只能使用字母、数字、_、-"; return 1; }
    name_exists "$name" && { echo "❌ 名称已存在。"; return 1; }

    case "$choice" in
        1|2)
            read -r -p "本地监听端口: " port
            valid_port "$port" || { echo "❌ 端口无效。"; return 1; }
            port_conflict "$port" && { echo "❌ 端口已占用。"; return 1; }
            read -r -p "目标地址: " host
            read -r -p "目标端口: " tport
            valid_port "$tport" || { echo "❌ 目标端口无效。"; return 1; }
            if [ "$choice" = 1 ]; then
                printf '%s|tcp|%s|%s|%s||||||||\n' "$name" "$port" "$host" "$tport" >> "$DB_FILE"
            else
                printf '%s|udp|%s|%s|%s||||||||\n' "$name" "$port" "$host" "$tport" >> "$DB_FILE"
            fi
            ;;
        3)
            read -r -p "Relay 服务端监听端口: " port
            valid_port "$port" || { echo "❌ 端口无效。"; return 1; }
            port_conflict "$port" && { echo "❌ 端口已占用。"; return 1; }
            transport="$(read_transport)" || { echo "❌ 选择无效。"; return 1; }

            secure="false"; sni=""; path="/ws"; ws_host=""; cert=""; key=""; ca=""
            if [ "$transport" = "tls" ] || [ "$transport" = "wss" ]; then
                read -r -p "证书文件路径（留空使用 GOST 默认/全局证书）: " cert
                read -r -p "私钥文件路径（留空使用 GOST 默认/全局证书）: " key
                read -r -p "CA 文件路径（可留空）: " ca
            fi
            if [ "$transport" = "ws" ] || [ "$transport" = "wss" ]; then
                read -r -p "WS Path [/ws]: " path
                [ -n "$path" ] || path="/ws"
                [[ "$path" == /* ]] || path="/$path"
                read -r -p "WS Host（可留空）: " ws_host
            fi
            printf '%s|relay_server|%s||%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "$name" "$port" "$port" "$transport" "$secure" "$sni" "$path" "$ws_host" "$cert" "$key" "$ca" >> "$DB_FILE"
            ;;
        4)
            read -r -p "本地监听端口: " port
            valid_port "$port" || { echo "❌ 端口无效。"; return 1; }
            port_conflict "$port" && { echo "❌ 端口已占用。"; return 1; }
            read -r -p "远端 Relay 地址: " host
            read -r -p "远端 Relay 端口: " tport
            valid_port "$tport" || { echo "❌ 远端端口无效。"; return 1; }
            transport="$(read_transport)" || { echo "❌ 选择无效。"; return 1; }

            secure="false"; sni=""; path="/ws"; ws_host=""; cert=""; key=""; ca=""
            if [ "$transport" = "tls" ] || [ "$transport" = "wss" ]; then
                read -r -p "验证服务器证书？(y/n，默认 n): " x
                [ "$x" = "y" ] && secure="true"
                read -r -p "TLS ServerName/SNI（可留空）: " sni
                read -r -p "CA 文件（可留空，用于证书锁定）: " ca
            fi
            if [ "$transport" = "ws" ] || [ "$transport" = "wss" ]; then
                read -r -p "WS Path [/ws]: " path
                [ -n "$path" ] || path="/ws"
                [[ "$path" == /* ]] || path="/$path"
                read -r -p "WS Host（可留空）: " ws_host
            fi
            printf '%s|relay_client|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "$name" "$port" "$host" "$tport" "$transport" "$secure" "$sni" "$path" "$ws_host" "$cert" "$key" "$ca" >> "$DB_FILE"
            ;;
        *) echo "❌ 无效选择。"; return 1;;
    esac

    apply_yaml
}

delete_task() {
    list_tasks || return 0
    local n name tmp
    read -r -p "删除任务编号: " n
    name="$(name_by_index "$n" 2>/dev/null || true)"
    [ -n "$name" ] || { echo "❌ 无效。"; return 1; }
    read -r -p "确认删除 [$name]？(y/n): " x
    [ "$x" = y ] || return 0
    tmp="$(mktemp)"
    awk -F'|' -v n="$name" '$1!=n{print}' "$DB_FILE" > "$tmp"
    mv -f "$tmp" "$DB_FILE"
    apply_yaml
}

show_status() {
    echo "========== GOST V2.1 =========="
    echo "版本：$(installed_version 2>/dev/null || echo 未安装)"
    if systemctl is-active --quiet gost.service 2>/dev/null; then
        echo "服务：🟢 Running"
    else
        echo "服务：🔴 Stopped/Failed"
    fi
    echo "配置：$CONFIG_FILE"
    echo
    list_tasks || true
}

show_config() { [ -f "$CONFIG_FILE" ] && cat "$CONFIG_FILE" || echo "❌ 配置不存在。"; }
show_logs() { journalctl -u gost.service -n 80 --no-pager; }

uninstall_gost() {
    read -r -p "彻底删除 GOST、配置和任务？(y/n): " x
    [ "$x" = y ] || return 0
    systemctl stop gost.service 2>/dev/null || true
    systemctl disable gost.service 2>/dev/null || true
    rm -f "$SYSTEMD_FILE" "$BINARY_PATH"
    systemctl daemon-reload
    rm -rf "$CONFIG_DIR"
    echo "✅ 已卸载。"
}

menu() {
    while true; do
        echo
        echo "================================================"
        echo "        GOST V3 管理脚本 V2.1"
        echo "================================================"
        echo "1. 安装 / 重装 GOST"
        echo "2. 检测并升级 GOST"
        echo "3. 卸载 GOST"
        echo "4. 新建 TCP/UDP/Relay 任务"
        echo "5. 删除任务"
        echo "6. 重启 GOST"
        echo "7. 查看状态"
        echo "8. 查看 YAML"
        echo "9. 查看日志"
        echo "0. 退出"
        echo "================================================"
        local x
        read -r -p "请选择: " x
        case "$x" in
            1) install_gost;;
            2) update_gost;;
            3) uninstall_gost;;
            4) create_task;;
            5) delete_task;;
            6) restart_gost;;
            7) show_status;;
            8) show_config;;
            9) show_logs;;
            0) exit 0;;
            *) echo "❌ 无效选择。";;
        esac
    done
}

main() {
    need_root
    ensure_tools || exit 1
    init_dirs
    menu
}
main "$@"
