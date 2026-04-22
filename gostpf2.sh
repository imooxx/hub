#!/usr/bin/env bash
# File: gostpf2.sh
# 功能：GOST v3 多端口转发服务管理工具

set -e

# ========== 辅助函数 ========== 

# 验证配置文件存在
validate_config() {
    if [[ ! -f "$1" ]]; then
        echo "❌ 配置文件不存在: $1"
        return 1
    fi
    return 0
}

# YAML 格式验证（yq 优先降级正则）
check_yaml_validity() {
    local config_file="$1"
    if command -v yq &>/dev/null; then
        if ! yq eval '.' "$config_file" > /dev/null 2>&1; then
            echo "❌ 配置文件 YAML 格式错误"
            return 1
        fi
    else
        # 降级方案：基础正则检查
        if ! grep -q 'services:' "$config_file"; then
            echo "❌ 配置文件缺少 services 节点"
            return 1
        fi
    fi
    return 0
}

# 安全提取最后一个端口
extract_last_port() {
    local config_file="$1"
    local port
    
    if command -v yq &>/dev/null; then
        port=$(yq eval '.services[-1].addr' "$config_file" 2>/dev/null | grep -oE '[0-9]+' | tail -1)
    else
        # 正则降级：仅匹配 "addr: \":PORT\"" 格式
        port=$(grep -E 'addr:\s*":"[0-9]+' "$config_file" | tail -1 | grep -oE '[0-9]+' | tail -1)
    fi
    
    # 验证端口有效性
    if [[ ! $port =~ ^[0-9]+$ ]] || [ "$port" -le 0 ] || [ "$port" -gt 65535 ]; then
        port=$DEFAULT_PORT
    fi
    
    echo "$port"
}

# 检查目录权限
check_dir_permissions() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || {
            echo "❌ 无法创建目录: $dir"
            return 1
        }
    fi
    if [[ ! -w "$dir" ]]; then
        echo "❌ 目录无写入权限: $dir"
            return 1
    fi
    return 0
}

# 服务健康检查（最多重试5次）
check_service_health() {
    local service_name="$1"
    local max_retries=5
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if systemctl is-active --quiet "$service_name"; then
            echo "✅ 服务启动成功"
            return 0
        fi
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            echo "⏳ 等待服务启动... ($retry_count/$max_retries)"
            sleep 1
        fi
    done
    
    echo "❌ 服务启动失败，查看日志:"
    systemctl status "$service_name" --no-pager || true
    return 1
}

# ========== 主程序 ========== 

# 1. Root 权限检查
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
  rm -rf "$CONFIG_DIR"
  systemctl daemon-reload

  echo "✅ GOST 卸载清理完成"

  echo "🧹 清理安装残留文件..."
  for file in LICENSE README.md README_en.md; do
    [[ -f "$PWD/$file" ]] && rm -f "$PWD/$file" && echo "🗑️ 删除 $PWD/$file"
  done
  exit 0
fi

# ========== 安装 GOST ========== 
if [[ "$CHOICE" == "1" ]]; then
  echo "👉 开始安装 GOST..."
  
  if ! bash <(curl -fsSL --connect-timeout 15 https://github.com/go-gost/gost/raw/master/install.sh); then
    echo "❌ 安装脚本下载或执行失败，请检查网络连接。"
    exit 1
  fi

  if [[ ! -x "$GOST_BIN" ]]; then
    echo "❌ GOST 未能成功安装到 $GOST_BIN，请重试。"
    exit 1
  fi
  echo "✅ GOST 安装成功：$GOST_BIN"

  # 检查目录权限
  if ! check_dir_permissions "$CONFIG_DIR"; then
    exit 1
  fi

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

  # 验证 YAML 格式
  if ! check_yaml_validity "$CONFIG_FILE"; then
    exit 1
  fi

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

  # 检查服务���康
  if ! check_service_health "$SERVICE_NAME"; then
    exit 1
  fi

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
  if ! validate_config "$CONFIG_FILE"; then
    echo "❌ 请先执行完整安装（选项 1）"
    exit 1
  fi

  # 验证 YAML
  if ! check_yaml_validity "$CONFIG_FILE"; then
    exit 1
  fi

  LAST_PORT=$(extract_last_port "$CONFIG_FILE")
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

  # 重启前验证
  if ! check_yaml_validity "$CONFIG_FILE"; then
    echo "❌ 配置验证失败，请检查 $CONFIG_FILE"
    exit 1
  fi

  systemctl restart "$SERVICE_NAME"
  
  # 检查服务健康
  if ! check_service_health "$SERVICE_NAME"; then
    exit 1
  fi
  
  echo "🎉 新节点已生效：监听 ${NEW_PORT}，转发至 ${TARGET_ADDR}"
  exit 0
fi

echo "❌ 无效的选择，脚本退出。"
exit 1