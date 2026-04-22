#!/usr/bin/env bash
# File: gostpf2.sh
# 功能：GOST v3 多端口转发服务管理工具

set -e

# 1. Root 权限检查 (必须拦截非 root 执行，否则操作 /etc 必定报错)
if [[ $EUID -ne 0 ]]; then
  echo "❌ 错误: 此脚本需要 root 权限，请使用 sudo 或 root 账号运行。"
  exit 1
fi

SERVICE_NAME="gost.service"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}"
CONFIG_DIR="/etc/gost"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
GOST_BIN="/usr/local/bin/gost"
DEFAULT_PORT=18080

echo -e "\033[1;36m====== GOST v3 多端口转发服务工具 ======\033[0m"
echo "1) 安装并配置 GOST"
echo "2) 添加一个转发节点"
echo "3) 卸载并清理 GOST"
read -p "请选择操作 [1/2/3]（默认 1）: " CHOICE
CHOICE=${CHOICE:-1}

# ========== 卸载 ==========
if [[ "$CHOICE" == "3" ]]; then
  echo "⚠️ 即将卸载 GOST 配置和服务..."

  if systemctl list-units --full -all | grep -q "${SERVICE_NAME}"; then
    systemctl stop "${SERVICE_NAME}" || true
    systemctl disable "${SERVICE_NAME}" || true
  fi

  rm -f "$SYSTEMD_FILE" "$CONFIG_FILE" "$GOST_BIN"
  rm -rf "$CONFIG_DIR"  # 直接清理整个配置目录更彻底
  systemctl daemon-reload

  echo "✅ GOST 卸载清理完成"

  # 优化：清理当前执行目录残留文件，避免硬编码 /root (用户可能在其他目录 wget/curl 脚本)
  echo "🧹 清理安装残留文件..."
  for file in LICENSE README.md README_en.md; do
    [[ -f "$PWD/$file" ]] && rm -f "$PWD/$file" && echo "🗑️ 删除 $PWD/$file"
  done
  exit 0
fi

# ========== 安装 GOST ==========
if [[ "$CHOICE" == "1" ]]; then
  echo "👉 开始安装 GOST..."
  
  # 增加网络超时处理，防止由于网络波动卡死
  if ! bash <(curl -fsSL --connect-timeout 15 https://github.com/go-gost/gost/raw/master/install.sh); then
    echo "❌ 安装脚本下载或执行失败，请检查网络连接。"
    exit 1
  fi

  if [[ ! -x "$GOST_BIN" ]]; then
    echo "❌ GOST 未能成功安装到 $GOST_BIN，请重试。"
    exit 1
  fi
  echo "✅ GOST 安装成功：$GOST_BIN"

  mkdir -p "$CONFIG_DIR"

  echo -e "\n\033[1;33m====== 配置第一个转发服务 ======\033[0m"
  read -p "请输入本地监听端口（默认 $DEFAULT_PORT）: " LISTEN_PORT
  LISTEN_PORT=${LISTEN_PORT:-$DEFAULT_PORT}

  read -p "请输入目标转发地址（如 192.168.1.100:80）: " TARGET_ADDR
  if [[ -z "$TARGET_ADDR" ]]; then
     echo "❌ 目标地址不能为空！"
     exit 1
  fi

  read -p "请输入该转发配置的名称（默认 portforward）: " FORWARD_NAME
  FORWARD_NAME=${FORWARD_NAME:-portforward}
  NODE_NAME="T${FORWARD_NAME}"

  # 规范化 YAML 格式，添加引号包裹，修正缩进
  cat > "$CONFIG_FILE" <<EOF
services:
  - name: "${FORWARD_NAME}"
    addr: ":${LISTEN_PORT}"
    handler:
      type: tcp
    listener:
      type: tcp
    forwarder:
      nodes:
        - name: "${NODE_NAME}"
          addr: "${TARGET_ADDR}"
EOF

  echo "✅ 已写入配置文件：$CONFIG_FILE"

  # 优化 Systemd 配置：添加最大文件描述符限制，并设置网络依赖
  cat > "$SYSTEMD_FILE" <<EOF
[Unit]
Description=GOST Forwarding Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${GOST_BIN} -C ${CONFIG_FILE}
Restart=always
RestartSec=5s
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"

  echo
  echo "🎉 GOST 已部署并运行"
  echo "查看状态命令： systemctl status ${SERVICE_NAME}"

  echo
  echo "🧹 清理安装残留文件..."
  for file in LICENSE README.md README_en.md; do
    [[ -f "$PWD/$file" ]] && rm -f "$PWD/$file" && echo "🗑️ 删除 $PWD/$file"
  done

  exit 0
fi

# ========== 添加转发节点 ==========
if [[ "$CHOICE" == "2" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ 配置文件不存在，请先执行完整安装（选项 1）"
    exit 1
  fi

  # 修复正则提取逻辑：兼容带/不带引号以及空格规范的 YAML 格式
  LAST_PORT=$(grep -E 'addr:\s*"?:[0-9]+' "$CONFIG_FILE" | tail -n1 | grep -oE '[0-9]+' || echo "$DEFAULT_PORT")
  SUGGESTED_PORT=$((LAST_PORT + 1))

  echo -e "\n\033[1;33m====== 添加转发节点 ======\033[0m"
  read -p "请输入本地监听端口（默认 $SUGGESTED_PORT）: " NEW_PORT
  NEW_PORT=${NEW_PORT:-$SUGGESTED_PORT}

  read -p "请输入目标转发地址（如 192.168.1.100:80）: " TARGET_ADDR
  if [[ -z "$TARGET_ADDR" ]]; then
    echo "❌ 目标地址不能为空！"
    exit 1
  fi

  read -p "请输入该转发配置的名称（默认 port${NEW_PORT}）: " FORWARD_NAME
  FORWARD_NAME=${FORWARD_NAME:-port${NEW_PORT}}
  NODE_NAME="T${FORWARD_NAME}"

  # 遵循与初始安装相同的缩进规范
  cat >> "$CONFIG_FILE" <<EOF
  - name: "${FORWARD_NAME}"
    addr: ":${NEW_PORT}"
    handler:
      type: tcp
    listener:
      type: tcp
    forwarder:
      nodes:
        - name: "${NODE_NAME}"
          addr: "${TARGET_ADDR}"
EOF

  echo "✅ 已添加转发服务到配置文件"

  systemctl restart "$SERVICE_NAME"
  echo "🎉 新节点已生效：监听 ${NEW_PORT}，转发至 ${TARGET_ADDR}"
  exit 0
fi

echo "❌ 无效的选择，脚本退出。"
exit 1
