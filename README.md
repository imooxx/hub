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
···
wget -O /root/gostpf.sh "https://raw.githubusercontent.com/imooxx/hub/refs/heads/main/gostpf.sh" && chmod +x /root/gostpf.sh && /root/gostpf.sh
···
