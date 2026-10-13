# ath10k-avm

Out-of-tree Build des `ath10k`-Treibers (Linux 7.0.9-Basis, läuft gegen 7.2.x) für den
**AVM FRITZ!WLAN USB Stick AC 430 MU-MIMO** (`057c:8602`, QCA9377 mit HL-Firmware).

- `main`: unveränderte `drivers/net/wireless/ath/ath10k` aus Linux v7.0.9 (nur `ath/*.h` und `ath10k/`).
- `avm-usb`: Änderungen. `git diff main avm-usb` ist der komplette Patch (~450 Zeilen).

## Änderungen (je ein Commit)

| Commit | Inhalt |
|---|---|
| USB-Gerät | USB-ID, `hw_params`-Eintrag (Firmware `QCA9377/avm`), Restart per Diag-Reset, Firmware wird beim Probe gebootet und von `ath10k_start()` übernommen |
| HL-Completion-FIFO | Die Firmware meldet in `TX_COMPL_IND` immer `msdu_id` 10/11; Completions werden stattdessen in FIFO-Reihenfolge zugeordnet |
| ACK-Filter | Nur jedes N-te reine TCP-ACK senden (`ack_thin`), weil die Firmware TX-Frames unaggregiert sendet |

## Modulparameter

| Modul | Parameter | Standard | Wirkung |
|---|---|---|---|
| `ath10k_core` | `ack_thin` | 0 | 0/1 = aus, N = nur jedes N-te reine ACK senden (empfohlen: 2) |
| `ath10k_core` | `ack_thin_pending` | 0 | nur ausdünnen, wenn mindestens so viele Frames in der Firmware warten (empfohlen: 8) |

`pkg/ath10k-avm.conf` setzt `ack_thin=2 ack_thin_pending=8`. Zur Laufzeit abschaltbar:
`echo 0 | sudo tee /sys/module/ath10k_core/parameters/ack_thin`

## Installation

Voraussetzungen: `kernel-devel` für den laufenden Kernel, Firmware in
`/lib/firmware/ath10k/QCA9377/avm/{firmware-usb-5.bin,board.bin}` (aus dem AVM-Windows-Treiber,
`fwuac430mu_wlan_w8.bin` / `fwuac430mu_bdata_w8.bin`; nicht Teil dieses Repos).

    sudo ./install.sh      # Quellen nach /usr/src/ath10k-avm, Module nach /lib/modules/<kver>/updates/
    sudo ./uninstall.sh

`ath10k-avm-rebuild.service` baut die Module nach einem Kernel-Update beim ersten Boot neu
(nur wenn für den laufenden Kernel noch keine existieren). Entwicklungsbuild ohne root:

    AVM_SRC=$PWD pkg/ath10k-avm-build "$(uname -r)" --build-only /tmp/out

## Funktionsweise in Kürze

- Ein Chip-Reset enumeriert den Stick neu. Deshalb bleibt die beim Probe gebootete Firmware
  laufen; jedes `stop` löst Reset und erneutes Probe aus (neues `wlan0` nach ~4 s).
- Reset-Sequenz wie beim AVM-Windows-Treiber: Diag-RMW `0x20c700` vor BMI, `WMI_PDEV_SUSPEND`,
  ~2 s Ruhe, dann Diag-Write `0x100` auf `SOC_RESET_CONTROL`. Schutz gegen Reset-Schleifen:
  höchstens 6 Resets pro 60 s.
- Die Firmware aggregiert TX nicht (1 MPDU je PPDU, ~300 µs je Frame). Unter Download-Last schafft
  sie ~1000–1700 Frames/s; TCP-ACKs deckeln den Download bei ~30 Mbit/s (UDP: ~48). Mit `ack_thin=2`
  steigt er auf ~44 Mbit/s; der Upload bleibt unverändert (Leitungsgrenze).

## Bekannte Grenzen

- Nur mit dem AVM-Stick getestet. Die USB-Änderungen gelten für alle `ath10k_usb`-Geräte
  (Linksys WUSB6100M ist in der ID-Tabelle, Reset und Pre-BMI-Sequenz sind aber auf die AVM-ID
  beschränkt).
- Ping zur Box steigt unter Download-Last auf ~35–60 ms (Warteschlange in der Firmware).
- Die Erkennung von Duplikat-ACKs merkt sich nur den letzten Flow.
- Beim Entladen des Moduls bei aktiver Schnittstelle meldet der Treiber
  `failed to delete WMI vdev -22` (Stick ist dann bereits suspendiert); nicht untersucht.
