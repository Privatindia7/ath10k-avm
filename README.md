# ath10k-avm — Linux driver for the AVM FRITZ!WLAN USB Stick AC 430 MU-MIMO

Out-of-tree build of the in-kernel `ath10k_usb` driver with the changes needed to make the
**AVM FRITZ!WLAN USB Stick AC 430 MU-MIMO** (USB ID `057c:8602`) work on Linux. The stick is
a Qualcomm Atheros **QCA9377** with the high-latency (HL) firmware; AVM only ships a Windows driver.

> Unofficial, unsupported, no affiliation with AVM or Qualcomm. "FRITZ!" is a trademark of AVM.
> You use this at your own risk; it replaces your system's `ath10k` modules (see
> [Caveats](#caveats)).
>
> **Status: works on 5 GHz. 2.4 GHz does not work reliably** (association times out, see
> [What does not work](#what-does-not-work--not-known)). If you can only use a 2.4 GHz network
> this is not a solution yet.

## What works

Tested on **Fedora 44 / Nobara 44, kernel 7.2.9, x86_64, NetworkManager, one FRITZ!Box on 5 GHz
(channel 52, 80 MHz)**:

- scan, associate (**5 GHz only**), DHCP, normal use as a station; encrypted connection with
  management frame protection
- `nmcli radio wifi off/on`, `ip link set wlan0 down/up`, module reload, reboot, autoload
- rebuild of the modules by a systemd service after a kernel update (verified once)
- TCP download with `ack_thin=2`: **~40 Mbit/s on average, 32–47 Mbit/s observed** (without the
  filter 26–33 Mbit/s, same signal, alternating runs: +41 %). The test DSL line syncs at
  53.7 Mbit/s and UDP download reaches 47.8 Mbit/s, so the line is the limit. Upload is at the
  line limit (~9.5–10 Mbit/s). At weaker signal (−61 dBm) a few runs showed up to ~1 %
  TCP retransmissions with the filter on (~0 with it off, where the stick is the bottleneck).
- CPU: ~1 % of one core at 45 Mbit/s; memory: about 1 MB (module 0.83 MB plus buffers)

## What does not work / not known

- **2.4 GHz does not work.** Tested against the 2.4 GHz radio of the same FRITZ!Box (channel 6,
  WPA2, signal ~67 %). In five attempts on one day: four times authentication succeeded and the
  association request timed out (3 tries), once the association succeeded and the AP dropped the
  client 2 s later with `4WAY_HANDSHAKE_TIMEOUT`. Scanning and receiving work (the AP is listed,
  authentication frames are answered), so it looks like our frames do not reach the AP reliably
  on 2.4 GHz. Cause not found: not yet known whether it is the stick's TX on 2.4 GHz (TX power /
  board data), the firmware, or router-side band steering. It was not tried against another
  2.4 GHz access point. The 5 GHz link of the same router works.
- **Not tested:** AP / monitor / P2P modes, suspend/resume, unplugging while connected, several
  sticks, Secure Boot, other distributions, other kernels (the code is based on Linux v7.0.9 and
  was built against 7.2.9 only), IPv6 ACK thinning (implemented, not explicitly verified), other
  access points, 5 GHz channels other than 52.
- **No TX aggregation.** The firmware sends every frame on its own (one MPDU per PPDU,
  ~300 µs of air time each). Under download load the stick can send only ~1000–1700 frames/s;
  without a workaround TCP ACKs cap the download at ~30 Mbit/s. `ack_thin` (below) works around
  this; a faster line may expose other limits.
- **Latency under load.** With a large download running, ping to the router rises from ~2 ms to
  35–60 ms (queue inside the firmware, spikes up to ~400 ms seen). Idle and light traffic
  (voice, games on their own) are fine: ~8 ms to the internet, no loss.
- **Every `down` resets the stick.** It re-enumerates and `wlan0` reappears after ~4–6 s
  (NetworkManager reconnects by itself). Do not expect an instant `down`/`up`.
- The driver refuses more than 6 stick resets per minute (loop guard against reset loops).
- Unloading the module while the interface is up logs `failed to delete WMI vdev -22` (the stick
  is already suspended at that point); harmless as far as observed, not investigated.

## Requirements

- Kernel headers/devel for the running kernel (`/lib/modules/$(uname -r)/build`), `make`, `gcc`
- Secure Boot off, or sign the modules yourself (they are unsigned out-of-tree modules)
- The firmware files (below)
- NetworkManager is optional; `pkg/nm-avm-managed.conf` disables MAC randomization for the stick

## Firmware

The firmware is proprietary and **not part of this repository**. Create it from files you
already have:

1. From the **AVM Windows driver** of the stick take `fwuac430mu_wlan_w8.bin`,
   `fwuac430mu_otp_w8.bin`, `fwuac430mu_bdata_w8.bin` (driver package version 11.3.4.0; in
   `C:\Windows\System32\DriverStore\FileRepository\fwuac430mux_w8.inf_*` once installed).
2. From **linux-firmware** take `ath10k/QCA9377/hw1.0/firmware-sdio-5.bin` (`.xz` is fine).
3. Convert and install:

       tools/make-firmware.py AVM_DIR /lib/firmware/ath10k/QCA9377/hw1.0/firmware-sdio-5.bin.xz out/
       sudo install -D -m 0644 out/firmware-usb-5.bin out/board.bin -t /lib/firmware/ath10k/QCA9377/avm/

   The AVM firmware uses the same SGMT segment format as the SDIO HL firmware; the script only
   repackages it into the ath10k container (IE layout of the SDIO file, version/FW/OTP replaced,
   `board.bin` = AVM board data unchanged). It needs only the Python standard library.

## Install / uninstall

    sudo ./install.sh        # sources to /usr/src/ath10k-avm, modules to /lib/modules/<kver>/updates/
    sudo ./uninstall.sh

Then reboot or reload: `sudo modprobe -r ath10k_usb ath10k_pci ath10k_sdio ath10k_core; sudo modprobe ath10k_usb`.
Development build without root:

    AVM_SRC=$PWD pkg/ath10k-avm-build "$(uname -r)" --build-only /tmp/out

If the rebuild service ever misbehaves at boot, add `systemd.mask=ath10k-avm-rebuild.service`
to the kernel command line.

## Module parameters

| Module | Parameter | Default | Effect |
|---|---|---|---|
| `ath10k_core` | `ack_thin` | 0 | 0/1 = off, N = send only every N-th plain TCP ACK (recommended 2) |
| `ath10k_core` | `ack_thin_pending` | 0 | thin only while at least this many frames wait in the firmware (recommended 8) |

`pkg/ath10k-avm.conf` installs `ack_thin=2 ack_thin_pending=8`. Switch off at runtime:
`echo 0 | sudo tee /sys/module/ath10k_core/parameters/ack_thin`

Only plain ACKs are thinned: no payload, ACK flag only, no SACK option, and not a repeat of the
previous ACK number. Duplicate ACKs, SACK and window updates always go out. With `ack_thin=3`
retransmissions increase strongly, so 2 is the useful value.

## How it works

`main` is the unmodified `drivers/net/wireless/ath/{*.h,ath10k/}` of Linux v7.0.9;
`avm-usb` holds the changes (`git diff main avm-usb`, ~450 lines), one commit each:

1. **USB device**: USB ID, `hw_params` entry (firmware dir `QCA9377/avm`), restart scheme. A
   second firmware boot is impossible without a chip reset and the reset re-enumerates the
   stick, so the firmware booted at probe is kept running and adopted by `ath10k_start()`; every
   stop resets the chip (sequence copied from the AVM Windows driver: diag read-modify-write of
   `0x20c700`, `WMI_PDEV_SUSPEND`, ~2 s idle, diag write `0x100` to `SOC_RESET_CONTROL`).
2. **HL completion FIFO**: the firmware reports `msdu_id` 10/11 in every `TX_COMPL_IND`, so
   completions never match and the pending slots leak until TX stalls. It sends exactly one
   completion per data frame, in order, so they are matched against a FIFO of in-flight frames.
3. **ACK filter**: see above.

The reasoning behind each change (what the Windows driver does, why the download stalled at
30 Mbit/s) is summarized in the commit messages.

## Caveats

- The modules go to `updates/` and **override the stock `ath10k_core/pci/sdio/usb` of your
  kernel** for all ath10k hardware. All four are installed on purpose: the patched
  `ath10k_core` has a different struct layout, so stock `ath10k_pci`/`ath10k_sdio` must not be
  mixed with it. The code is a v7.0.9 snapshot; on a different kernel it may lack newer upstream
  fixes. `install.sh` refuses to run if the machine has a PCI/SDIO ath10k device (override with
  `--force`).
- Every workaround (restart/keep-alive scheme, suspend option, completion FIFO, ACK thinning)
  is gated on USB vendor `057c`; other ath10k devices, including other USB ones, keep the
  upstream code paths.
- Restarting the stick (every `down`, suspend, firmware recovery) waits ~2 s inside the driver
  while holding `conf_mutex` and, on interface down, the RTNL lock; other network configuration
  stalls for that time. Whether the wait is needed at all is untested.
- Do not expect upstream acceptance: it is a workaround for one firmware, not a general fix.

## License

The files under `drivers/` come from the Linux kernel and keep their original licenses (almost
all ISC; see the per-file SPDX tags and license headers, our changes use the license of the file
they are in). Scripts and documentation (`install.sh`, `pkg/`, `tools/`, this file): ISC, see
`LICENSE`.
