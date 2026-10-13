#!/bin/bash
# Installiert den gepatchten ath10k-Treiber (FRITZ!WLAN USB Stick AC 430) dauerhaft.
# Rueckgaengig: sudo ./uninstall.sh      Aufruf: sudo ./install.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Bitte als root: sudo $0" >&2; exit 1; }
P="$(dirname "$(readlink -f "$0")")"
DST=/usr/src/ath10k-avm
A=drivers/net/wireless/ath
FW=/lib/firmware/ath10k/QCA9377/avm

# The patched ath10k_core has a different struct layout than the stock one, so
# ath10k_pci and ath10k_sdio come from the same tree and replace the stock
# modules for every ath10k device of this machine. Refuse if there is one.
if [ "${1:-}" != "--force" ]; then
	other=$(find /sys/bus/pci/drivers/ath10k_pci /sys/bus/sdio/drivers/ath10k_sdio \
		-mindepth 1 -maxdepth 1 -type l ! -name module 2>/dev/null | wc -l)
	if [ "$other" -gt 0 ]; then
		echo "This machine has $other PCI/SDIO ath10k device(s) that would also run on the patched" >&2
		echo "modules (a v7.0.9 snapshot). Use '$0 --force' if that is what you want." >&2
		exit 1
	fi
fi

if [ ! -f "$FW/firmware-usb-5.bin" ] || [ ! -f "$FW/board.bin" ]; then
	echo "Firmware missing in $FW (firmware-usb-5.bin, board.bin): create it with tools/make-firmware.py, see README" >&2
	exit 1
fi

echo "[1/5] Quellen nach $DST"
rm -rf "$DST"
install -d "$DST/$A/ath10k"
cp -a "$P/$A"/*.h "$DST/$A/"
cp -a "$P/$A/ath10k/." "$DST/$A/ath10k/"

echo "[2/5] Skript, Dienst, Modulparameter"
install -m 0755 "$P/pkg/ath10k-avm-build" /usr/local/sbin/ath10k-avm-build
install -m 0644 "$P/pkg/ath10k-avm-rebuild.service" /etc/systemd/system/ath10k-avm-rebuild.service
install -m 0644 "$P/pkg/ath10k-avm.conf" /etc/modprobe.d/ath10k-avm.conf
command -v restorecon >/dev/null && restorecon /usr/local/sbin/ath10k-avm-build \
	/etc/systemd/system/ath10k-avm-rebuild.service /etc/modprobe.d/ath10k-avm.conf || true
systemctl daemon-reload
systemctl enable ath10k-avm-rebuild.service

echo "[3/5] NetworkManager-Einstellungen (MAC des Sticks)"
MAC=""
for d in /sys/class/net/*; do
	[ "$(basename "$(readlink -f "$d/device/driver" 2>/dev/null)")" = ath10k_usb ] && MAC="$(cat "$d/address")" && break
done
if [ -n "$MAC" ]; then
	sed "s/@MAC@/$MAC/" "$P/pkg/nm-avm-managed.conf" > /etc/NetworkManager/conf.d/99-avm-managed.conf
	nmcli general reload conf || true
else
	echo "      Stick nicht gefunden (ath10k_usb nicht geladen): ausgelassen, pkg/nm-avm-managed.conf manuell einsetzen"
fi

echo "[4/5] Module fuer $(uname -r) bauen und installieren"
/usr/local/sbin/ath10k-avm-build "$(uname -r)"

echo "[5/5] Fertig. Aktivieren: Neustart oder"
echo "      sudo modprobe -r ath10k_usb ath10k_pci ath10k_sdio ath10k_core; sudo modprobe ath10k_usb"
