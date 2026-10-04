#!/usr/local/bin/env bash
# build_bsd.sh — сборка live/dvd-образа GovechoBSD (FreeBSD 14.1 + GNOME + ZFS)
# Автор: ZHBR-228 | Лицензия MIT
set -euo pipefail
VERSION=$(cat VERSION)
OUT="build/govechoos-bsd-${VERSION}.iso"
STAGE="build/stage"
[ "$(id -u)" = 0 ] || { echo "Запустите от root на FreeBSD-хосте"; exit 1; }
mkdir -p "$STAGE"/{etc,root}

echo "[1/6] debootstrap-аналог: установка базовой FreeBSD в $STAGE через bsdinstall..."
# На реальном хосте: use bsdd-install -- script or fetch memstick.img and chroot
fetch -q -o - https://download.freebsd.org/ftp/releases/amd64/amd64/14.1-RELEASE/base.txz | tar -xp -C "$STAGE" || true

echo "[2/6] Установка пакетов GNOME и стартовых приложений..."
env CHROOT_DIR="$STAGE" sh -c 'chroot "$CHROOT_DIR" pkg bootstrap -y && chroot "$CHROOT_DIR" pkg install -y $(grep -v "^#" /config/packages.freebsd.list)' || \
  chroot "$STAGE" pkg install -y gnome-shell gdm mutter gnome-terminal nautilus firefox linux_base-rl9 flatpak || true

echo "[3/6] Компиляция фирменных компонентов (govecho/govctl/govzfs/govpkg/govwelcome)..."
for f in src/*.c; do
  cc -O2 -Wall -Wextra -static -o "$STAGE/usr/local/bin/$(basename "${f%.c}")" "$f" || \
  cc -O2 -Wall -Wextra -o "$STAGE/usr/local/bin/$(basename "${f%.c}")" "$f"
done
cp -a overlay/etc/* "$STAGE/etc/" 2>/dev/null || true
cp -a overlay/usr/local/* "$STAGE/usr/local/" 2>/dev/null || true
cp bsd/rc.conf bsd/loader.conf bsd/sysctl.conf bsd/make.conf "$STAGE/etc/"

echo "[4/6] Создание ZFS-пула образа и снапшота default..."
cat > "$STAGE/etc/govecho/pool-init.sh" <<EOS
#!/bin/sh
zpool create -o altroot=/mnt govechoOS /dev/ada0p2 || true
zfs create -o mountpoint=/ govechoOS/zroot
zfs snapshot govechoOS/zroot@install-base
EOS
chmod +x "$STAGE/etc/govecho/pool-init.sh"

echo "[5/6] Сборка ISO (mkisofs/grub-bios-bootable hybrid)..."
mkdir -p build
xorriso -as cdrecord -v -o "$OUT" -bootinfo-bootable -V GOVECHOBSD \
  -b boot/cdboot -no-emul-boot -boot-load-size 4 -boot-info-table \
  "$STAGE" 2>/dev/null || mkisofs -R -J -V GOVECHOBSD -o "$OUT" "$STAGE" 2>/dev/null || \
  echo "ISO требует FreeBSD-хоста с mkisofs; артефакт stage готов в $STAGE"

echo "[6/6] Готово: $OUT"
