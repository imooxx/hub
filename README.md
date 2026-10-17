### jsDelivr CDN
`https://cdn.jsdelivr.net/gh/imooxx/hub/`

### Output base information
`bash <(curl -L -s https://raw.githubusercontent.com/imooxx/hub/refs/heads/main/info.sh)`

### Update base on v2ray-agent
`bash <(curl -L -s https://raw.githubusercontent.com/imooxx/hub/refs/heads/main/xupdate.sh)`

### Gost v3 install
```
bash <(curl -L -s https://raw.githubusercontent.com/imooxx/hub/refs/heads/main/gostv3cdn.sh)
bash <(curl -L -s https://cdn.jsdelivr.net/gh/imooxx/hub@master/gostv3cdn.sh)
```

### Rsust_manage.sh
```
wget -O /root/rsust_manage.sh "https://raw.githubusercontent.com/imooxx/hub/refs/heads/main/rsust_manage.sh" && chmod +x /root/rsust_manage.sh && ln -sf /root/rsust_manage.sh /usr/local/bin/rsust && rsust
```

### GostPF.sh
```
wget -O /root/gostpf.sh "https://raw.githubusercontent.com/imooxx/hub/refs/heads/main/gostpf.sh" && chmod +x /root/gostpf.sh && /root/gostpf.sh
```
### Manage_swap.sh
```
wget -O /root/manage_swap.sh "https://raw.githubusercontent.com/imooxx/hub/refs/heads/main/manage_swap.sh" && chmod +x /root/manage_swap.sh && /root/manage_swap.sh
```
### Latency.sh
From:[https://github.com/Cd1s/network-latency-tester](https://github.com/Cd1s/network-latency-tester)
```
wget -O /root/latency.sh "https://raw.githubusercontent.com/imooxx/hub/refs/heads/main/latency.sh" && chmod +x /root/latency.sh && /root/latency.sh
```

### xshortidup.sh
```
wget -O /root/xshortidup.sh "https://raw.githubusercontent.com/imooxx/hub/refs/heads/main/xshortidup.sh" && chmod +x /root/xshortidup.sh && /root/xshortidup.sh
```
```
wget -O /root/xshortidup.sh "https://cdn.jsdelivr.net/gh/imooxx/hub@master/xshortidup.sh" && chmod +x /root/xshortidup.sh && /root/xshortidup.sh
```

### d_install_outv4_monitor.sh
Check out IPv4 address on Debian12&Debian13, detected every hour, and the generated information is recorded in outv4.log in the root folder.
```
wget -O /root/d_install_outv4_monitor.sh "https://raw.githubusercontent.com/imooxx/hub/refs/heads/main/d_install_outv4_monitor.sh" && chmod +x /root/d_install_outv4_monitor.sh && /root/d_install_outv4_monitor.sh
```

### a_install_outv4_monitor.sh
Check out IPv4 address on Alpine3.21, detected every hour, and the generated information is recorded in outv4.log in the root folder.
```
wget -O /root/a_install_outv4_monitor.sh "https://raw.githubusercontent.com/imooxx/hub/refs/heads/main/a_install_outv4_monitor.sh" && chmod +x /root/a_install_outv4_monitor.sh && /root/a_install_outv4_monitor.sh
```
### mgost.sh
```
wget -O /root/mgost.sh "https://raw.githubusercontent.com/imooxx/hub/refs/heads/main/mgost.sh" && chmod +x /root/mgost.sh && /root/mgost.sh
```

### amgost.sh for Alpine3.23
```
wget -O /root/amgost.sh "https://raw.githubusercontent.com/imooxx/hub/refs/heads/main/amgost.sh" && chmod +x /root/amgost.sh && /root/amgost.sh
```
