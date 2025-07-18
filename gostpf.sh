#!/usr/bin/env bash
# File: gostpf.sh
# 功能：GOST v3 多端口转发服务管理工具

set -e

SERVICE_NAME="gost.service"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}"
CONFIG_DIR="/etc/gost"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
GOST_BIN="/usr/local/bin/gost"
DEFAULT_PORT=18080

echo "====== GOST v3 多端口转发服务工具 ======"
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
  rmdir --ignore-fail-on-non-empty "$CONFIG_DIR" 2>/dev/null || true
  systemctl daemon-reload

  echo "✅ GOST 卸载清理完成"

  # 清理 /root 文件
  echo "🧹 清理 /root 中无用文件..."
  for file in LICENSE README.md README_en.md; do
    [[ -f "/root/$file" ]] && rm -f "/root/$file" && echo "🗑️ 删除 /root/$file"
  done
  exit 0
fi

# ========== 安装 GOST ==========
if [[ "$CHOICE" == "1" ]]; then
  echo "👉 开始安装 gost..."
  bash <(curl -fsSL https://github.com/go-gost/gost/raw/master/install.sh)

  if [[ ! -x "$GOST_BIN" ]]; then
    echo "❌ 安装失败，请检查网络或重试"
    exit 1
  fi
  echo "✅ gost 安装成功：$GOST_BIN"

  mkdir -p "$CONFIG_DIR"
  > "$CONFIG_FILE" # 清空配置文件

  echo "====== 配置第一个转发服务 ======"
  read -p "请输入本地监听端口（默认 $DEFAULT_PORT）: " LISTEN_PORT
  LISTEN_PORT=${LISTEN_PORT:-$DEFAULT_PORT}

  read -p "请输入目标转发地址（如 192.168.1.100:80）: " TARGET_ADDR
  [[ -z "$TARGET_ADDR" ]] && echo "❌ 目标地址不能为空！" && exit 1

  read -p "请输入该转发配置的名称（默认 portforward）: " FORWARD_NAME
  FORWARD_NAME=${FORWARD_NAME:-portforward}
  NODE_NAME="T${FORWARD_NAME}"

  cat > "$CONFIG_FILE" <<EOF
services:
- name: ${FORWARD_NAME}
  addr: :${LISTEN_PORT}
  handler:
    type: tcp
  listener:
    type: tcp
  forwarder:
    nodes:
    - name: ${NODE_NAME}
      addr: "${TARGET_ADDR}"
EOF

  echo "✅ 已写入配置文件：$CONFIG_FILE"

  cat > "$SYSTEMD_FILE" <<EOF
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

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"

  echo
  echo "🎉 GOST 已部署并运行"
  echo "查看状态： systemctl status ${SERVICE_NAME}"

  echo
  echo "🧹 清理 /root 中无用文件..."
  for file in LICENSE README.md README_en.md; do
    [[ -f "/root/$file" ]] && rm -f "/root/$file" && echo "🗑️ 删除 /root/$file"
  done

  exit 0
fi

# ========== 添加转发节点 ==========
if [[ "$CHOICE" == "2" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ 配置文件不存在，请先执行完整安装（选项1）"
    exit 1
  fi

  # 提取最后一个端口
  LAST_PORT=$(grep 'addr: ":*[0-9]*"' "$CONFIG_FILE" | tail -n1 | grep -oE '[0-9]+' || echo "$DEFAULT_PORT")
  SUGGESTED_PORT=$((LAST_PORT + 1))

  echo "====== 添加转发节点 ======"
  read -p "请输入本地监听端口（默认 $SUGGESTED_PORT）: " NEW_PORT
  NEW_PORT=${NEW_PORT:-$SUGGESTED_PORT}

  read -p "请输入目标转发地址（如 192.168.1.100:80）: " TARGET_ADDR
  [[ -z "$TARGET_ADDR" ]] && echo "❌ 目标地址不能为空！" && exit 1

  read -p "请输入该转发配置的名称（默认 port${NEW_PORT}）: " FORWARD_NAME
  FORWARD_NAME=${FORWARD_NAME:-port${NEW_PORT}}
  NODE_NAME="T${FORWARD_NAME}"

  cat >> "$CONFIG_FILE" <<EOF

- name: ${FORWARD_NAME}
  addr: :${NEW_PORT}
  handler:
    type: tcp
  listener:
    type: tcp
  forwarder:
    nodes:
    - name: ${NODE_NAME}
      addr: "${TARGET_ADDR}"
EOF

  echo "✅ 已添加转发服务到配置文件"

  systemctl restart "$SERVICE_NAME"
  echo "🎉 新节点已生效：监听 ${NEW_PORT}，转发至 ${TARGET_ADDR}"
  exit 0
fi
