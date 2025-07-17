#!/usr/bin/env bash
# File: gostpf.sh
# 功能：交互式部署或卸载 GOST v3 端口转发服务

set -e

SERVICE_NAME="gost.service"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}"
CONFIG_DIR="/etc/gost"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
GOST_BIN="/usr/local/bin/gost"

# ========== 提供功能选择 ==========
echo "====== GOST v3 转发服务工具 ======"
echo "1) 安装并配置 GOST"
echo "2) 卸载并清理 GOST"
read -p "请选择操作 [1/2]（默认 1）: " CHOICE
CHOICE=${CHOICE:-1}

# ========== 卸载模式 ==========
if [[ "$CHOICE" == "2" ]]; then
  echo "⚠️ 即将卸载 GOST 配置和服务..."

  # 停止并禁用服务
  if systemctl list-units --full -all | grep -q "${SERVICE_NAME}"; then
    systemctl stop "${SERVICE_NAME}" || true
    systemctl disable "${SERVICE_NAME}" || true
    echo "✅ 已停止并禁用 systemd 服务"
  fi

  # 删除 systemd 文件
  if [[ -f "$SYSTEMD_FILE" ]]; then
    rm -f "$SYSTEMD_FILE"
    echo "🗑️ 已删除 systemd 文件: $SYSTEMD_FILE"
  fi

  # 删除配置文件和目录
  if [[ -f "$CONFIG_FILE" ]]; then
    rm -f "$CONFIG_FILE"
    echo "🗑️ 已删除配置文件: $CONFIG_FILE"
  fi
  if [[ -d "$CONFIG_DIR" ]]; then
    rmdir --ignore-fail-on-non-empty "$CONFIG_DIR" 2>/dev/null || true
  fi

  # 删除 gost 可执行文件（可选）
  if [[ -f "$GOST_BIN" ]]; then
    read -p "是否同时删除 gost 主程序（$GOST_BIN）？[y/N]: " DEL_BIN
    if [[ "$DEL_BIN" == "y" || "$DEL_BIN" == "Y" ]]; then
      rm -f "$GOST_BIN"
      echo "🗑️ 已删除 gost 主程序"
    fi
  fi

  # 清除缓存并提示
  systemctl daemon-reload
  echo "✅ GOST 卸载清理完成。"
  exit 0
fi

# ========== 安装模式 ==========
echo "====== GOST v3 转发服务配置 ======"

# 输入监听端口，默认 10800
read -p "请输入本地监听端口（默认 10800）: " LISTEN_PORT
LISTEN_PORT=${LISTEN_PORT:-10800}

# 输入目标地址
read -p "请输入目标转发地址（如 192.168.1.100:80）: " TARGET_ADDR
if [[ -z "$TARGET_ADDR" ]]; then
  echo "❌ 目标地址不能为空！"
  exit 1
fi

# 输入转发配置名称，默认 portforward
read -p "请输入该转发配置的名称（默认 portforward）: " FORWARD_NAME
FORWARD_NAME=${FORWARD_NAME:-portforward}

# 安装 gost
echo "👉 开始安装 gost..."
bash <(curl -fsSL https://github.com/go-gost/gost/raw/master/install.sh)

# 自动检测 gost 是否安装成功
if [[ -x "${GOST_BIN}" ]]; then
  echo "✅ 经检测，${GOST_BIN} 已存在，gost 安装成功。"
else
  echo "⚠️ 未检测到 ${GOST_BIN}，请确认安装是否成功。"
  read -p "是否继续执行配置？(y/n): " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "❌ 用户中止操作，请检查 gost 安装后重试。"
    exit 1
  fi
fi

# 创建配置目录
mkdir -p "${CONFIG_DIR}"

# 生成配置文件（节点名为 T+FORWARD_NAME）
NODE_NAME="T${FORWARD_NAME}"

cat > "${CONFIG_FILE}" <<EOF
services:
- name: ${FORWARD_NAME}
  addr: ":${LISTEN_PORT}"
  handler:
    type: tcp
  listener:
    type: tcp
  forwarder:
    nodes:
    - name: ${NODE_NAME}
      addr: ${TARGET_ADDR}
EOF

echo "✅ 已生成配置文件：${CONFIG_FILE}"

# 写入 systemd 服务
cat > "${SYSTEMD_FILE}" <<EOF
[Unit]
Description=gost forwarding service
After=network.target

[Service]
Type=simple
ExecStart=${GOST_BIN} -C ${CONFIG_FILE}
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动服务
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

# 提示信息
echo
echo "🎉 GOST 已部署并运行"
echo "监听端口: ${LISTEN_PORT}"
echo "目标地址: ${TARGET_ADDR}"
echo "转发名称: ${FORWARD_NAME}"
echo "节点名称: ${NODE_NAME}"
echo
echo "查看状态：  systemctl status ${SERVICE_NAME}"
echo "重启服务：  systemctl restart ${SERVICE_NAME}"
