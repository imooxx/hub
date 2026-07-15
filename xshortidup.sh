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
JSON_FILE_07="/etc/v2ray-agent/xray/conf/07_VLESS_vision_reality_inbounds.json"
BACKUP_FILE_07="/etc/v2ray-agent/xray/conf/07_VLESS_vision_reality_inbounds.jsonbackup"

JSON_FILE_12="/etc/v2ray-agent/xray/conf/12_VLESS_XHTTP_inbounds.json"
BACKUP_FILE_12="/etc/v2ray-agent/xray/conf/12_VLESS_XHTTP_inbounds.jsonbackup"

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

# 2. 检测 JSON 配置文件及目标 shortIds
echo "🔄 [步骤 2/5] 正在检测 JSON 配置文件..."
if [ ! -f "$JSON_FILE_07" ]; then
    echo "❌ 错误：未找到主配置文件 $JSON_FILE_07"
    exit 1
fi

# 检查 07 文件中是否包含目标 ID
CHECK_ID_07=$(jq --arg id "$OLD_ID" '.inbounds[].streamSettings.realitySettings.shortIds | select(. != null) | contains([$id])' "$JSON_FILE_07" 2>/dev/null)
if [ -z "$CHECK_ID_07" ] || ! echo "$CHECK_ID_07" | grep -q "true"; then
    if ! grep -q "$OLD_ID" "$JSON_FILE_07"; then
        echo "❌ 错误：未在主配置文件 $JSON_FILE_07 中找到目标 shortId ($OLD_ID)，脚本退出。"
        exit 1
    fi
fi
echo "  - 配置文件 07_VLESS_vision_reality_inbounds.json 检测通过"

# 动态检测是否存在 12 文件并包含目标 ID
HAS_FILE_12=false
if [ -f "$JSON_FILE_12" ]; then
    echo "  - 检测到可选配置文件 12_VLESS_XHTTP_inbounds.json，正在验证..."
    if grep -q "$OLD_ID" "$JSON_FILE_12"; then
        HAS_FILE_12=true
        echo "  - 配置文件 12_VLESS_XHTTP_inbounds.json 检测通过（包含目标 ID）"
    else
        echo "  - 提示：12_VLESS_XHTTP_inbounds.json 中未找到目标 shortId ($OLD_ID)，将不对其进行修改。"
    fi
else
    echo "  - 提示：未检测到可选配置文件 12_VLESS_XHTTP_inbounds.json，将跳过其相关操作。"
fi

# 3. 备份并生成新 shortId 进行替换
echo "🔄 [步骤 3/5] 正在备份原文件并生成新的 shortId..."

# 备份 07 文件
cp "$JSON_FILE_07" "$BACKUP_FILE_07"
if [ $? -eq 0 ]; then
    echo "  - 备份成功：$BACKUP_FILE_07"
else
    echo "❌ 错误：07 配置文件备份失败，脚本退出。"
    exit 1
fi

# 备份 12 文件（如果存在且匹配成功）
if [ "$HAS_FILE_12" = true ]; then
    cp "$JSON_FILE_12" "$BACKUP_FILE_12"
    if [ $? -eq 0 ]; then
        echo "  - 备份成功：$BACKUP_FILE_12"
    else
        echo "❌ 错误：12 配置文件备份失败，脚本退出。"
        # 安全回滚 07 的备份
        rm -f "$BACKUP_FILE_07"
        exit 1
    fi
fi

# 生成 16 位随机字符 (8字节 hex)
NEW_ID=$(openssl rand -hex 8)
echo "  - 成功生成新的 shortId: $NEW_ID"

# 替换 07 文件中的原有字符
sed -i "s/$OLD_ID/$NEW_ID/g" "$JSON_FILE_07"

# 替换 12 文件中的原有字符（如果存在且匹配成功）
if [ "$HAS_FILE_12" = true ]; then
    sed -i "s/$OLD_ID/$NEW_ID/g" "$JSON_FILE_12"
fi

# 4. 保存验证并重启服务
echo "🔄 [步骤 4/5] 正在验证并重启 Xray 服务..."

# 验证 07 替换后的 JSON 格式是否依然合法
if ! jq '.' "$JSON_FILE_07" > /dev/null 2>&1; then
    echo "❌ 警告：$JSON_FILE_07 替换后的 JSON 格式不合法！正在从备份恢复..."
    cp "$BACKUP_FILE_07" "$JSON_FILE_07"
    if [ "$HAS_FILE_12" = true ]; then
        cp "$BACKUP_FILE_12" "$JSON_FILE_12"
    fi
    exit 1
fi

# 验证 12 替换后的 JSON 格式是否依然合法
if [ "$HAS_FILE_12" = true ]; then
    if ! jq '.' "$JSON_FILE_12" > /dev/null 2>&1; then
        echo "❌ 警告：$JSON_FILE_12 替换后的 JSON 格式不合法！正在全面从备份恢复..."
        cp "$BACKUP_FILE_07" "$JSON_FILE_07"
        cp "$BACKUP_FILE_12" "$JSON_FILE_12"
        exit 1
    fi
fi

echo "  - 📝 替换成功！旧 ID [$OLD_ID] -> 新 ID [$NEW_ID]"

# 重启服务
echo "  - 正在重启 xray.service..."
service xray restart
if [ $? -eq 0 ] && systemctl is-active --quiet xray.service; then
    echo "  - Xray 服务重启成功！"
else
    echo "❌ 错误：Xray 服务重启失败，正在尝试从备份恢复配置..."
    cp "$BACKUP_FILE_07" "$JSON_FILE_07"
    if [ "$HAS_FILE_12" = true ]; then
        cp "$BACKUP_FILE_12" "$JSON_FILE_12"
    fi
    service xray restart
    echo "  - 已全面恢复原配置文件，请检查日志 (journalctl -u xray)。"
    exit 1
fi

# 5. 完成
echo "======================================"
echo "🎉 [步骤 5/5] 脚本运行完成！所有操作已成功结束。"
echo "======================================"
