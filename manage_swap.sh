#!/bin/bash
set -e

SWAPFILE="/swapfile"
ACTION=""
SIZE_MB=""

function show_info {
  echo "Current swap status:"
  free -h
  swapon --show || echo "No swap currently active."
}

function add_swap {
  read -p "Enter swap size in MiB (e.g. 512, 2048): " SIZE_MB

  if ! [[ "$SIZE_MB" =~ ^[0-9]+$ ]]; then
    echo "Invalid input. Please enter a positive integer (in MiB)."
    exit 1
  fi

  echo "Creating swapfile of ${SIZE_MB}MiB..."

  fallocate -l "${SIZE_MB}M" "${SWAPFILE}" 2>/dev/null || dd if=/dev/zero of="${SWAPFILE}" bs=1M count="${SIZE_MB}" status=progress

  chmod 600 "${SWAPFILE}"
  mkswap "${SWAPFILE}"
  swapon "${SWAPFILE}"

  if ! grep -q "${SWAPFILE}" /etc/fstab; then
    echo "${SWAPFILE} swap swap defaults 0 0" >> /etc/fstab
  fi

  echo "Swapfile created and enabled."

  read -p "Set vm.swappiness to 10 for better performance? (y/n): " yn
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    echo "vm.swappiness=10" > /etc/sysctl.d/99-swappiness.conf
    sysctl -p /etc/sysctl.d/99-swappiness.conf
    echo "Swappiness set to 10."
  fi
}

function remove_swap {
  if swapon --show | grep -q "${SWAPFILE}"; then
    swapoff "${SWAPFILE}"
    echo "Swapfile deactivated."
  else
    echo "Swapfile not active."
  fi

  sed -i "\|${SWAPFILE}|d" /etc/fstab
  rm -f "${SWAPFILE}"
  echo "Swapfile removed and fstab cleaned."
}

# Main menu
echo "=== Swap Manager for Debian 12 ==="
show_info
echo

echo "Choose an action:"
echo "  1) Add swap"
echo "  2) Remove swap"
echo "  0) Exit"
read -p "Enter your choice: " ACTION

case "$ACTION" in
  1)
    add_swap
    ;;
  2)
    remove_swap
    ;;
  0)
    echo "Exiting."
    ;;
  *)
    echo "Invalid choice. Exiting."
    ;;
esac

echo
show_info
