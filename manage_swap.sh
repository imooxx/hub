#!/bin/bash
set -e

SWAPFILE="/swapfile"
ACTION=""
SIZE_GB=""

function show_info {
  echo "当前 Swap 情况："
  free -h
  swapon --show
}

function add_swap {
  read -p "请输入要创建的 swap 大小（GiB，例如 2）： " SIZE_GB
  fallocate -l "${SIZE_GB}G" "${SWAPFILE}"
  chmod 600 "${SWAPFILE}"
  mkswap "${SWAPFILE}"
  swapon "${SWAPFILE}"
  echo "${SWAPFILE} swap swap defaults 0 0" >> /etc/fstab
  echo "已创建并激活 ${SIZE_GB} GiB swap 文件：${SWAPFILE}"
  read -p "是否设置 vm.swappiness=10？(y/n) " yn
  if [[ $yn =~ ^[Yy]$ ]]; then
    echo "vm.swappiness=10" >> /etc/sysctl.d/99-swappiness.conf
    sysctl -p /etc/sysctl.d/99-swappiness.conf
    echo "已设置 swappiness=10"
  fi
}

function remove_swap {
  if swapon --show | grep -q "${SWAPFILE}"; then
    swapoff -v "${SWAPFILE}"
    echo "已停用 swapfile"
  else
    echo "swapfile 当前未激活"
  fi
  sed -i "\|${SWAPFILE}|d" /etc/fstab
  rm -f "${SWAPFILE}"
  echo "/etc/fstab 中相关行已删除，swapfile 已删除"
}

# 主菜单
echo "=== Debian 12 一键管理 Swap 脚本 ==="
show_info
echo

echo "请选择操作："
echo "  1) 添加 Swap 文件"
echo "  2) 删除 Swap 文件"
echo "  0) 退出"
read -p "输入数字选择： " ACTION

case "$ACTION" in
  1)
    add_swap
    ;;
  2)
    remove_swap
    ;;
  0)
    echo "退出。"
    ;;
  *)
    echo "无效选择。退出。"
    ;;
esac

echo
show_info
