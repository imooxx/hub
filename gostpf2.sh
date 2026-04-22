# ========== 安装 GOST ========== 
if [[ "$CHOICE" == "1" ]]; then
  echo "👉 开始安装 GOST..."
  
  # 添加重试逻辑
  RETRY_COUNT=0
  MAX_RETRIES=3
  INSTALL_SUCCESS=false
  
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "📥 尝试下载安装脚本 ($((RETRY_COUNT + 1))/$MAX_RETRIES)..."
    if bash <(curl -fsSL --connect-timeout 30 --max-time 120 https://github.com/go-gost/gost/raw/master/install.sh); then
      INSTALL_SUCCESS=true
      break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo "⚠️ 第 $RETRY_COUNT 次尝试失败，5 秒后重试..."
      sleep 5
    fi
  done
  
  if ! $INSTALL_SUCCESS; then
    echo "❌ 安装脚本下载或执行失败，请检查网络连接。"
    exit 1
  fi

  if [[ ! -x "$GOST_BIN" ]]; then
    echo "❌ GOST 未能成功安装到 $GOST_BIN，请重试。"
    exit 1
  fi
  echo "✅ GOST 安装成功：$GOST_BIN"