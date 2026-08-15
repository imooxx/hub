#!/bin/bash
set -e

# 安装 curl（如果没有）
if ! command -v curl >/dev/null 2>&1; then
    apt-get update
    apt-get install -y curl
fi

# 创建检测脚本
cat >/root/check_outv4.sh <<'EOS'
#!/bin/bash

LOG="/root/outv4.log"
STATE="/root/.outv4_last_ip"
TIME=$(date '+%Y-%m-%d %H:%M:%S')

IP=$(curl -4 -fsS --max-time 15 https://ifconfig.me 2>/dev/null | tr -d '[:space:]')

if [ -z "$IP" ]; then
    echo "$TIME | IPv4: FAILED" >> "$LOG"
    exit 1
fi

if [ ! -f "$STATE" ]; then
    echo "$IP" > "$STATE"
    echo "$TIME | IPv4: $IP | INITIAL" >> "$LOG"
    exit 0
fi

OLD=$(cat "$STATE")

if [ "$IP" = "$OLD" ]; then
    echo "$TIME | IPv4: $IP | UNCHANGED" >> "$LOG"
else
    echo "$TIME | IPv4: $IP | CHANGED | OLD: $OLD" >> "$LOG"
    echo "$IP" > "$STATE"
fi
EOS

chmod 700 /root/check_outv4.sh

# 创建 Service
cat >/etc/systemd/system/outv4-check.service <<'EOS'
[Unit]
Description=Outbound IPv4 Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/root/check_outv4.sh
EOS

# 创建 Timer（严格整点）
cat >/etc/systemd/system/outv4-check.timer <<'EOS'
[Unit]
Description=Run IPv4 Monitor Hourly

[Timer]
OnCalendar=hourly
Persistent=true
AccuracySec=1s
RandomizedDelaySec=0

[Install]
WantedBy=timers.target
EOS

touch /root/outv4.log
chmod 600 /root/outv4.log

systemctl daemon-reload
systemctl enable --now outv4-check.timer

# 立即执行一次，避免等待到下一个整点
systemctl start outv4-check.service

echo
echo "====================== 部署完成 ======================"
echo
systemctl list-timers outv4-check.timer --no-pager
echo
echo "当前日志："
cat /root/outv4.log
