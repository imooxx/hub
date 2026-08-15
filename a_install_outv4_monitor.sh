#!/bin/sh

echo "=========================================="
echo " Alpine 3.21 IPv4 Monitor"
echo "=========================================="

if [ "$(id -u)" != "0" ]; then
    echo "ERROR: Please run as root."
    exit 1
fi

if [ ! -f /etc/alpine-release ]; then
    echo "ERROR: This is not Alpine Linux."
    exit 1
fi

echo "Alpine version: $(cat /etc/alpine-release)"

# 安装 curl
if ! command -v curl >/dev/null 2>&1; then
    echo "Installing curl..."
    apk add --no-cache curl
fi

# 创建检测脚本
cat > /root/check_outv4.sh <<'SCRIPT'
#!/bin/sh

LOG="/root/outv4.log"
STATE="/root/.outv4_last_ip"

NOW="$(date '+%Y-%m-%d %H:%M:%S')"

IP="$(curl -4 -fsS --max-time 15 https://ifconfig.me 2>/dev/null | tr -d '[:space:]')"

if [ -z "$IP" ]; then
    echo "$NOW | IPv4: FAILED" >> "$LOG"
    exit 1
fi

if [ ! -f "$STATE" ]; then
    echo "$IP" > "$STATE"
    echo "$NOW | IPv4: $IP | INITIAL" >> "$LOG"
    exit 0
fi

OLD_IP="$(cat "$STATE")"

if [ "$IP" = "$OLD_IP" ]; then
    echo "$NOW | IPv4: $IP | UNCHANGED" >> "$LOG"
else
    echo "$NOW | IPv4: $IP | CHANGED | OLD: $OLD_IP" >> "$LOG"
    echo "$IP" > "$STATE"
fi

exit 0
SCRIPT

chmod 700 /root/check_outv4.sh

touch /root/outv4.log
chmod 600 /root/outv4.log

# 创建 Alpine 每小时任务目录
mkdir -p /etc/periodic/hourly

# 创建 hourly 任务
cat > /etc/periodic/hourly/outv4check <<'SCRIPT'
#!/bin/sh
exec /root/check_outv4.sh
SCRIPT

chmod 700 /etc/periodic/hourly/outv4check

# 确保 crond 开机启动
rc-update add crond default >/dev/null 2>&1

# 启动或重启 crond
if rc-service crond status >/dev/null 2>&1; then
    rc-service crond restart
else
    rc-service crond start
fi

# 立即执行一次测试
/root/check_outv4.sh

echo
echo "=========================================="
echo " Installation completed"
echo "=========================================="
echo
echo "Alpine version:"
cat /etc/alpine-release
echo
echo "crond status:"
rc-service crond status
echo
echo "Hourly script:"
ls -l /etc/periodic/hourly/outv4check
echo
echo "Check script:"
ls -l /root/check_outv4.sh
echo
echo "Current log:"
cat /root/outv4.log
echo
echo "Schedule:"
echo "Every hour at minute 00"
echo
echo "Log:"
echo "/root/outv4.log"
echo
