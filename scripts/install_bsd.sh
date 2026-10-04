#!/usr/local/bin/env bash
# install_bsd.sh — установщик GovechoBSD на диск (ZFS-корень + GNOME)
# Автор: ZHBR-228 | MIT
set -euo pipefail
DISK="${1:-ada0}"
[ "$(id -u)" = 0 ] || { echo "root required"; exit 1; }

echo "[1/4] Разметка GPT на $DISK..."
gpart destroy -F "$DISK" 2>/dev/null || true
gpart create -s GPT "$DISK"
gpart add -t freebsd-boot -l bootme -s 512k "$DISK"
gpart add -t freebsd-zfs -l govecho -s 20G "$DISK"
gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 "$DISK"

echo "[2/4] Создание пула govechoOS и датасетов..."
zpool create -o altroot=/mnt -O canmount=off govechoOS "/dev/${DISK}s2"
zfs create -o mountpoint=/ -o canmount=noauto govechoOS/zroot
zfs create govechoOS/zroot/usr govechoOS/zroot/var/log govechoOS/data/home
zfs snapshot govechoOS/zroot@install-base

echo "[3/4] Копирование stage-системы и конфигурации..."
rsync -aHAX build/stage/ /mnt/ || cp -a build/stage/. /mnt/
cp bsd/rc.conf bsd/loader.conf bsd/sysctl.conf /mnt/etc/
mkdir -p /mnt/boot && echo 'vfs.root.mountfrom="zfs:govechoOS/zroot"' >> /mnt/boot/loader.conf

echo "[4/4] Финальная проверка загрузки..."
chroot /mnt /bin/sh -c 'test -x /usr/local/bin/govctl && govctl status' || true
echo "Готово. Перезагрузитесь: shutdown -r now"
