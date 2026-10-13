#!/bin/bash
# Entfernt den dauerhaft installierten ath10k-Treiber wieder. Aufruf: sudo ./uninstall.sh
set -u
[ "$(id -u)" = 0 ] || { echo "Bitte als root: sudo $0" >&2; exit 1; }
modprobe -r ath10k_usb ath10k_pci ath10k_sdio ath10k_core 2>/dev/null
systemctl disable ath10k-avm-rebuild.service 2>/dev/null
rm -f /etc/systemd/system/ath10k-avm-rebuild.service /etc/modprobe.d/ath10k-avm.conf \
	/usr/local/sbin/ath10k-avm-build /etc/NetworkManager/conf.d/99-avm-managed.conf \
	/etc/NetworkManager/conf.d/99-avm-unmanaged.conf
for d in /lib/modules/*/updates/ath10k-avm; do
	[ -d "$d" ] || continue
	k="$(basename "$(dirname "$(dirname "$d")")")"
	rm -rf "$d"
	rmdir "$(dirname "$d")" 2>/dev/null
	depmod -a "$k"
done
rm -rf /usr/src/ath10k-avm
systemctl daemon-reload
nmcli general reload conf 2>/dev/null
echo "Entfernt. Firmware unter /lib/firmware/ath10k/QCA9377/avm bleibt (zum Loeschen: sudo rm -r dieses Verzeichnis)."
