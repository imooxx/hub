
#!/bin/ash
# GOST v3.3.0 TCP Forward Manager
# Alpine Linux 3.23 / LXC / BusyBox ash

set -u

VERSION="3.3.0"
BASE="/etc/gost-forward"
RULES="$BASE/rules"
PIDS="$BASE/pids"
LOGS="/var/log/gost-forward"
BIN="/usr/local/bin/gost"
INIT="/etc/init.d/gost-forward"

mkdir -p "$RULES" "$PIDS" "$LOGS"

say() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; }
pause() { printf '\n按回车继续...'; read -r _; }

install_gost() {
    apk add --no-cache ca-certificates curl tar gzip >/dev/null || {
        err "依赖安装失败"
        return 1
    }

    arch="$(uname -m)"
    case "$arch" in
        x86_64) asset="linux_amd64" ;;
        aarch64|arm64) asset="linux_arm64" ;;
        i386|i686) asset="linux_386" ;;
        armv7l|armv7) asset="linux_armv7" ;;
        *)
            err "暂不支持架构：$arch"
            return 1
            ;;
    esac

    tmp="/tmp/gost-${VERSION}.tar.gz"
    url="https://github.com/go-gost/gost/releases/download/v${VERSION}/gost_${VERSION}_${asset}.tar.gz"

    say "下载 GOST v$VERSION ($asset)"
    curl -fL --retry 3 "$url" -o "$tmp" || {
        err "下载失败，请检查网络或 GitHub 连通性"
        return 1
    }

    tar -tzf "$tmp" >/dev/null 2>&1 || {
        err "安装包校验失败"
        rm -f "$tmp"
        return 1
    }

    tmpdir="$(mktemp -d)"
    tar -xzf "$tmp" -C "$tmpdir" || {
        rm -rf "$tmpdir" "$tmp"
        return 1
    }

    if [ ! -f "$tmpdir/gost" ]; then
        err "安装包内未找到 gost 可执行文件"
        rm -rf "$tmpdir" "$tmp"
        return 1
    fi

    chmod 755 "$tmpdir/gost"
    "$tmpdir/gost" -V >/dev/null 2>&1 || {
        err "GOST 无法运行，可能与容器架构或运行环境不兼容"
        rm -rf "$tmpdir" "$tmp"
        return 1
    }

    # 先验证新版本，再替换现有程序
    cp "$tmpdir/gost" "$BIN.new" &&
        chmod 755 "$BIN.new" &&
        mv -f "$BIN.new" "$BIN" || {
            rm -rf "$tmpdir" "$tmp"
            return 1
        }

    rm -rf "$tmpdir" "$tmp"
    say "安装完成：$("$BIN" -V 2>&1 | head -n 1)"
}

valid_port() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1 ] 2>/dev/null &&
        [ "$1" -le 65535 ] 2>/dev/null
}

valid_target() {
    # 接受 IPv4、IPv6 或域名形式的 host:port / [IPv6]:port
    target="$1"
    case "$target" in
        \[*\]:*)
            host="${target%%]*}"
            host="${host#\[}"
            port="${target##*:}"
            [ -n "$host" ] && valid_port "$port"
            ;;
        *:*)
            host="${target%:*}"
            port="${target##*:}"
            [ -n "$host" ] && valid_port "$port"
            ;;
        *) return 1 ;;
    esac
}

add_rule() {
    [ -x "$BIN" ] || {
        err "请先安装 GOST"
        return 1
    }

    printf "本地监听端口："
    read -r lp
    valid_port "$lp" || {
        err "无效端口"
        return 1
    }

    printf "目标地址 (例如 1.2.3.4:80 或 [2001:db8::1]:80)："
    read -r target
    valid_target "$target" || {
        err "目标地址或端口格式错误"
        return 1
    }

    file="$RULES/$lp"
    [ ! -e "$file" ] || {
        err "本地端口 $lp 已有规则"
        return 1
    }

    # 只允许简单 host:port 格式，防止参数注入
    printf '%s\n' "$target" > "$file"
    chmod 600 "$file"
    say "已添加：TCP :$lp -> $target"
}

list_rules() {
    printf '\n%-12s %-35s %s\n' "监听端口" "转发目标" "状态"
    for file in "$RULES"/*; do
        [ -f "$file" ] || continue
        lp="${file##*/}"
        target="$(cat "$file")"
        if [ -f "$PIDS/$lp" ] &&
            kill -0 "$(cat "$PIDS/$lp")" 2>/dev/null; then
            status="运行中"
        else
            status="已停止"
        fi
        printf '%-12s %-35s %s\n' "$lp" "$target" "$status"
    done
    printf '\n'
}

start_rule() {
    lp="$1"
    file="$RULES/$lp"
    [ -f "$file" ] || return 1

    if [ -f "$PIDS/$lp" ] &&
        kill -0 "$(cat "$PIDS/$lp")" 2>/dev/null; then
        return 0
    fi

    rm -f "$PIDS/$lp"
    target="$(cat "$file")"
    nohup "$BIN" -L "tcp://:$lp/$target" \
        >> "$LOGS/$lp.log" 2>&1 </dev/null &
    pid=$!
    echo "$pid" > "$PIDS/$lp"
    sleep 1

    if kill -0 "$pid" 2>/dev/null; then
        say "启动成功：:$lp -> $target"
    else
        rm -f "$PIDS/$lp"
        err "启动失败，查看日志：$LOGS/$lp.log"
        return 1
    fi
}

start_all() {
    [ -x "$BIN" ] || {
        err "请先安装 GOST"
        return 1
    }

    found=0
    for file in "$RULES"/*; do
        [ -f "$file" ] || continue
        found=1
        start_rule "${file##*/}" || true
    done

    [ "$found" -eq 1 ] || err "尚未添加转发规则"
}

stop_rule() {
    lp="$1"
    pidfile="$PIDS/$lp"
    [ -f "$pidfile" ] || return 0

    pid="$(cat "$pidfile")"
    case "$pid" in
        ''|*[!0-9]*) rm -f "$pidfile"; return 0 ;;
    esac

    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        n=0
        while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 5 ]; do
            sleep 1
            n=$((n + 1))
        done
        kill -9 "$pid" 2>/dev/null || true
    fi

    rm -f "$pidfile"
    say "已停止端口 $lp"
}

stop_all() {
    for file in "$RULES"/*; do
        [ -f "$file" ] || continue
        stop_rule "${file##*/}"
    done
}

delete_rule() {
    printf "要删除的本地监听端口："
    read -r lp
    valid_port "$lp" || {
        err "无效端口"
        return 1
    }

    [ -f "$RULES/$lp" ] || {
        err "规则不存在"
        return 1
    }

    stop_rule "$lp"
    rm -f "$RULES/$lp"
    say "规则已删除"
}

enable_autostart() {
    command -v rc-update >/dev/null 2>&1 || {
        err "当前容器未检测到 OpenRC，无法通过此方式设置开机启动"
        return 1
    }

    cat > "$INIT" <<'EOF'
#!/sbin/openrc-run

description="GOST TCP Forward Manager"

start() {
    ebegin "Starting GOST TCP forwarding"
    /bin/ash /usr/local/sbin/gost-forward start
    eend $?
}

stop() {
    ebegin "Stopping GOST TCP forwarding"
    /bin/ash /usr/local/sbin/gost-forward stop
    eend $?
}
EOF
    chmod 755 "$INIT"
    rc-update add gost-forward default
    rc-service gost-forward restart
    say "已配置 OpenRC 开机启动"
}

menu() {
    while :; do
        printf '\n===== GOST TCP 转发管理器 =====\n'
        printf '1. 安装/更新 GOST v%s\n' "$VERSION"
        printf '2. 添加 TCP 转发规则\n'
        printf '3. 查看规则\n'
        printf '4. 启动全部规则\n'
        printf '5. 停止全部规则\n'
        printf '6. 重启全部规则\n'
        printf '7. 删除规则\n'
        printf '8. 配置 OpenRC 开机启动\n'
        printf '9. 查看 GOST 版本\n'
        printf '0. 退出\n'
        printf '请选择：'
        read -r choice

        case "$choice" in
            1) install_gost ;;
            2) add_rule ;;
            3) list_rules ;;
            4) start_all ;;
            5) stop_all ;;
            6) stop_all; start_all ;;
            7) delete_rule ;;
            8) enable_autostart ;;
            9)
                if [ -x "$BIN" ]; then "$BIN" -V
                else err "GOST 尚未安装"; fi
                ;;
            0) exit 0 ;;
            *) err "无效选项" ;;
        esac
        pause
    done
}

case "${1:-menu}" in
    install) install_gost ;;
    add) add_rule ;;
    list) list_rules ;;
    start) start_all ;;
    stop) stop_all ;;
    restart) stop_all; start_all ;;
    menu) menu ;;
    *)
        echo "用法：$0 {install|add|list|start|stop|restart|menu}"
        exit 1
        ;;
esac
