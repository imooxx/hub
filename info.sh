# 获取系统信息
system_info=$(uname -a | awk '{print $1, $2, $3}')
cpu_info=$(grep -m 1 "model name" /proc/cpuinfo | cut -d ':' -f 2 | sed 's/^ *//')
cpu_cores=$(grep -c ^processor /proc/cpuinfo)
cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')

# 获取所有 /dev/ 开头的磁盘信息
disk_info=$(df -h | awk '/^\/dev\// {print $1, $3"/"$2, "("$5")"}' | tr '\n' ';' | sed 's/;$/ /')

# 获取内存信息
memory_total=$(free -m | awk '/Mem:/ {print $2}')
memory_used=$(free -m | awk '/Mem:/ {print $3}')
memory_percent=$(free -m | awk '/Mem:/ {printf "%.2f%%", ($3/$2)*100}')


# 获取所有网卡的流量信息，并找到流量最大的网卡
max_network_info=$(awk 'NR > 2 {rx+=$2; tx+=$10} END {printf "%.2fG|%.2fG", rx/1024/1024/1024, tx/1024/1024/1024}' /proc/net/dev)

# 拆分最大流量的接收和发送部分
network_in=$(echo "$max_network_info" | cut -d '|' -f1)
network_out=$(echo "$max_network_info" | cut -d '|' -f2)

# 获取系统负载
load_info=$(awk '{printf "%.2f/%.2f/%.2f", $1, $2, $3}' /proc/loadavg)

# 获取进程数
process_count=$(ps -e | wc -l)

# 获取连接数
tcp_connections=$(ss -t | grep -c ESTAB)
udp_connections=$(ss -u | grep -c UNCONN)

# 获取在线时间
uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
uptime_days=$((uptime_seconds / 86400))

# 输出信息
echo "系统: $system_info"
echo "CPU: $cpu_info $cpu_cores Virtual Core ($cpu_usage)"
echo "硬盘: $disk_info"
echo "内存: $memory_used"M"/$memory_total"M" ($memory_percent)"
echo "流量: IN $network_in OUT $network_out"
echo "负载: $load_info"
echo "进程数: $process_count"
echo "连接数: TCP $tcp_connections UDP $udp_connections"
echo "在线: $uptime_days 天"
