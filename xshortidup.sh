#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 错误：请使用 root 权限运行此脚本！"
    exit 1
fi

# 自动安装 jq 工具（用于安全解析和修改 JSON）
if ! command -v jq &> /dev/null; then
    echo "🔄 正在安装必要的 JSON 处理工具 jq..."
    apt-get update && apt-get install -y jq
fi

# 定义路径和变量
TARGET_DIR="/etc/v2ray-agent/"
JSON_FILE="/etc/v2ray-agent/xray/conf/07_VLESS_vision_reality_inbounds.json"
BACKUP_FILE="/etc/v2ray-agent/xray/conf/07_VLESS_vision_reality_inbounds.jsonbackup"
OLD_ID="6ba85179e30d4fc2"

echo "======================================"
echo "          Xray shortIds 更新脚本        "
echo "======================================"

# 1. 检测目录和 xray.service 状态
echo "🔄 [步骤 1/5] 正在检测系统环境..."
if [ ! -d "$TARGET_DIR" ]; then
    echo "❌ 错误：未检测到目录 $TARGET_DIR，脚本退出。"
    exit 1
fi

if ! systemctl is-active --quiet xray.service; then
    echo "❌ 错误：xray.service 未在运行，脚本退出。"
    exit 1
fi
echo "  - 系统环境检测通过（目录存在且 xray 服务正在运行）"

# 2. 检测 JSON 文件及目标 shortIds
echo "🔄 [步骤 2/5] 正在检测 JSON 配置文件..."
if [ ! -f "$JSON_FILE" ]; then
    echo "❌ 错误：未找到配置文件 $JSON_FILE"
    exit 1
fi

# 使用 jq 检查 shortIds 数组中是否包含指定的 ID
CHECK_ID=$(jq --arg id "$OLD_ID" '.inbounds[].streamSettings.realitySettings.shortIds | select(. != null) | contains([$id])' "$JSON_FILE" 2>/dev/null)

# 如果上面的通用路径没匹配到，尝试直接匹配根级或标准数组位置
if [ -z "$CHECK_ID" ] || ! echo "$CHECK_ID" | grep -q "true"; then
    # 备用方案：直接读取整个文件内容搜索字符串，确保兼容不同的 JSON 结构
    if ! grep -q "$OLD_ID" "$JSON_FILE"; then
        echo "❌ 错误：未在配置文件中找到目标 shortId ($OLD_ID)，脚本退出。"
        exit 1
    fi
fi
echo "  - 目标 shortId 匹配成功"

# 3. 备份并生成新 shortId 进行替换
echo "🔄 [步骤 3/5] 正在备份原文件并生成新的 shortId..."
cp "$JSON_FILE" "$BACKUP_FILE"
if [ $? -eq 0 ]; then
    echo "  - 备份成功：$BACKUP_FILE"
else
    echo "❌ 错误：备份失败，脚本退出。"
    exit 1
fi

# 生成 16 位随机字符 (8字节 hex)
NEW_ID=$(openssl rand -hex 8)
echo "  - 成功生成新的 shortId: $NEW_ID"

# 替换文件中的原有字符
# 使用 sed 进行精确替换
sed -i "s/$OLD_ID/$NEW_ID/g" "$JSON_FILE"

# 4. 保存验证并重启服务
echo "🔄 [步骤 4/5] 正在验证并重启 Xray 服务..."
# 检查替换后的 JSON 格式是否依然合法，防止配置损坏
if ! jq '.' "$JSON_FILE" > /dev/null 2>&1; then
    echo "❌ 警告：替换后的 JSON 格式不合法！正在从备份恢复..."
    cp "$BACKUP_FILE" "$JSON_FILE"
    exit 1
fi

echo "  - 📝 替换成功！旧 ID [$OLD_ID] -> 新 ID [$NEW_ID]"

# 重启服务
echo "  - 正在重启 xray.service..."
service xray restart

if [ $? -eq 0 ] && systemctl is-active --quiet xray.service; then
    echo "  - Xray 服务重启成功！"
else
    echo "❌ 错误：Xray 服务重启失败，请检查日志 (journalctl -u xray)。"
    exit 1
fi

# 5. 完成
echo "======================================"
echo "🎉 [步骤 5/5] 脚本运行完成！所有操作已成功结束。"
echo "======================================"
