#!/bin/bash

# 定义Xray目录
XRAY_DIR="/etc/v2ray-agent/xray/"

# 更新包列表并安装必要工具
apt update
apt install -y curl unzip

# 检查目录是否存在
if [ ! -d "$XRAY_DIR" ]; then
    echo "目录 $XRAY_DIR 不存在，终止执行。"
    exit 1
fi

echo "目录 $XRAY_DIR 存在，继续执行更新..."

# 停止Xray服务
service xray stop

echo "已停止Xray服务，开始检查Xray-core更新..."

# 获取Xray-core最新版本号及是否为Pre-release
XRAY_API_RESPONSE=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest)
XRAY_LATEST=$(echo "$XRAY_API_RESPONSE" | grep "tag_name" | cut -d '"' -f 4)
XRAY_PRERELEASE=$(echo "$XRAY_API_RESPONSE" | grep "prerelease" | awk '{print $2}' | tr -d ',')

if [ "$XRAY_PRERELEASE" == "true" ]; then
    echo "检测到最新版本为Pre-release，跳过Xray-core更新。"
else
    XRAY_ZIP="Xray-linux-64.zip"
    XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_LATEST}/${XRAY_ZIP}"

    # 下载并解压Xray-core
    curl -L -o "/tmp/${XRAY_ZIP}" "$XRAY_URL"
    unzip -o "/tmp/${XRAY_ZIP}" -d "$XRAY_DIR"
    rm "/tmp/${XRAY_ZIP}"

    echo "Xray-core更新完成，版本: $XRAY_LATEST"
fi

# 更新geoip.dat 和 geosite.dat
echo "开始更新geoip.dat和geosite.dat..."

RULES_LATEST=$(curl -s https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases/latest | grep "tag_name" | cut -d '"' -f 4)
GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${RULES_LATEST}/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${RULES_LATEST}/geosite.dat"

curl -L -o "${XRAY_DIR}/geoip.dat" "$GEOIP_URL"
curl -L -o "${XRAY_DIR}/geosite.dat" "$GEOSITE_URL"

echo "geoip.dat和geosite.dat更新完成，版本: $RULES_LATEST"

# 启动Xray服务并检查状态
service xray start

# 等待5秒钟
echo "等待5秒钟..."
sleep 5

service xray status

# 在服务状态输出后显示版本信息
echo "Xray-core 最新版本: $XRAY_LATEST"
echo "GeoIP 和 GeoSite 数据文件 最新版本: $RULES_LATEST"
