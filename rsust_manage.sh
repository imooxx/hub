#!/bin/bash

set -e

INSTALL_DIR="/usr/bin/shadowsocks-rust"
CONFIG_DIR="/etc/shadowsocks-rust"
SERVICE_FILE="/etc/systemd/system/shadowsocks-rust.service"
MANAGE_SCRIPT="/root/ssrust_manage.sh"
COMMAND_PATH="/usr/local/bin/rsust"

# ========== 公共函数 ==========
check_jq_installed() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "正在安装 jq ..."
        apt update && apt install -y jq
    fi
}

get_latest_release_version() {
    curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | jq -r '.tag_name' | sed 's/^v//'
}

get_public_ipv4() {
    ip addr | awk '/inet /{print $2}' | cut -d/ -f1 | \
    grep -vE '^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|127\.|169\.254\.)' | head -n1
}

get_public_ipv6() {
    ip -6 addr | awk '/inet6 /{print $2}' | cut -d/ -f1 | \
    grep -vE '^(::1|fe80|fc00|fd00)' | head -n1
}

# ========== 安装 ==========
install_shadowsocks() {
    check_jq_installed
    apt install -y curl xz-utils

    LATEST_VERSION=$(get_latest_release_version)
    echo "检测到最新版为 v$LATEST_VERSION"
    read -rp "是否继续安装？(按回车继续) " _

    ARCH="x86_64-unknown-linux-gnu"
    FILENAME="shadowsocks-v${LATEST_VERSION}.${ARCH}.tar.xz"
    URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${LATEST_VERSION}/${FILENAME}"

    cd /root && mkdir -p shadowsocks-tmp && cd shadowsocks-tmp
    curl -LO "$URL"
    tar -xf "$FILENAME"

    mkdir -p "$INSTALL_DIR"
    cp ssserver "$INSTALL_DIR/"

    cd /root && rm -rf shadowsocks-tmp

    mkdir -p "$CONFIG_DIR"

    read -rp "请输入端口（20000-39999，默认随机）： " server_port
    server_port=${server_port:-$((RANDOM%20000+20000))}

    read -rp "请输入密码（留空为随机生成）： " password
    if [ -z "$password" ]; then
        password=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+=' < /dev/urandom | head -c16)
    fi

    cat > "$CONFIG_DIR/config.json" <<EOF
{
    "server":"::",
    "server_port":$server_port,
    "password":"$password",
    "timeout":600,
    "method":"chacha20-ietf-poly1305",
    "fast_open":false
}
EOF

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Shadowsocks-Rust Service
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=${INSTALL_DIR}/ssserver -c ${CONFIG_DIR}/config.json
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable shadowsocks-rust
    systemctl start shadowsocks-rust
    echo "安装完成 ✅"
}

# ========== 升级 ==========
upgrade_shadowsocks() {
    check_jq_installed
    LATEST_VERSION=$(get_latest_release_version)
    echo "检测到最新版为 v$LATEST_VERSION"

    CURRENT_VERSION=$("$INSTALL_DIR/ssserver" -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        echo "当前已是最新版 v$CURRENT_VERSION，无需升级。"
        return
    fi

    read -rp "是否将 v$CURRENT_VERSION 升级到 v$LATEST_VERSION？(按回车继续) " _

    ARCH="x86_64-unknown-linux-gnu"
    FILENAME="shadowsocks-v${LATEST_VERSION}.${ARCH}.tar.xz"
    URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${LATEST_VERSION}/${FILENAME}"

    cd /root && mkdir -p shadowsocks-up && cd shadowsocks-up
    curl -LO "$URL"
    tar -xf "$FILENAME"

    systemctl stop shadowsocks-rust
    cp ssserver "$INSTALL_DIR/"

    cd /root && rm -rf shadowsocks-up
    systemctl start shadowsocks-rust
    echo "升级完成 ✅"
}

# ========== 卸载 ==========
uninstall_shadowsocks() {
    systemctl stop shadowsocks-rust
    systemctl disable shadowsocks-rust
    rm -rf "$INSTALL_DIR" "$CONFIG_DIR" "$SERVICE_FILE"
    systemctl daemon-reload
    echo "已卸载 Shadowsocks-Rust"
}

# ========== 状态控制 ==========
start_service() { systemctl start shadowsocks-rust && echo "服务已启动"; }
stop_service() { systemctl stop shadowsocks-rust && echo "服务已停止"; }
restart_service() { systemctl restart shadowsocks-rust && echo "服务已重启"; }
show_status() { systemctl status shadowsocks-rust; }

# ========== ss:// 输出 ==========
show_ss_link() {
    config="$CONFIG_DIR/config.json"
    if [ ! -f "$config" ]; then
        echo "配置文件不存在，请先安装。"
        return
    fi

    port=$(jq -r '.server_port' "$config")
    pass=$(jq -r '.password' "$config")
    method="chacha20-ietf-poly1305"
    userinfo=$(echo -n "${method}:${pass}" | base64 | tr -d '=')

    # 获取公网 IPv4 和 IPv6
    ipv4=$(curl -s https://ipinfo.io/ip)
    ipv6=$(curl -s https://api6.ipify.org)

    echo "———— Shadowsocks 链接信息 ————"
    if [[ -n "$ipv4" && "$ipv4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "🔹 IPv4:"
        echo "ss://${userinfo}@${ipv4}:${port}"
    fi

    if [[ -n "$ipv6" && "$ipv6" == *:* ]]; then
        echo "🔹 IPv6:"
        echo "ss://${userinfo}@[${ipv6}]:${port}"
    fi

    if [[ -z "$ipv4" && -z "$ipv6" ]]; then
        echo "⚠️ 无法获取公网地址，使用本地回环地址："
        echo "ss://${userinfo}@127.0.0.1:${port}"
    fi
}

# ========== 菜单 ==========
main_menu() {
    echo -e "\nShadowsocks-Rust 管理脚本"
    echo "1. 安装"
    echo "2. 升级"
    echo "3. 卸载"
    echo "4. 启动服务"
    echo "5. 停止服务"
    echo "6. 重启服务"
    echo "7. 查看服务状态"
    echo "8. 显示 ss:// 链接"
    echo "0. 退出"

    read -rp "请输入选项 [0-8]: " choice
    case $choice in
        1) install_shadowsocks ;;
        2) upgrade_shadowsocks ;;
        3) uninstall_shadowsocks ;;
        4) start_service ;;
        5) stop_service ;;
        6) restart_service ;;
        7) show_status ;;
        8) show_ss_link ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
}

# 添加全局命令
if [ ! -f "$COMMAND_PATH" ]; then
    echo "#!/bin/bash" > "$COMMAND_PATH"
    echo "bash $MANAGE_SCRIPT" >> "$COMMAND_PATH"
    chmod +x "$COMMAND_PATH"
    echo "已创建全局命令：rsust"
fi

# 主循环
while true; do
    main_menu
done
