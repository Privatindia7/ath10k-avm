#!/usr/bin/env python3
"""Build the ath10k firmware files for the AVM FRITZ!WLAN USB Stick AC 430 from
files you already have. Nothing proprietary is shipped in this repository.

  make-firmware.py AVM_DIR SDIO_FW OUTDIR [--label STRING]

  AVM_DIR  directory with fwuac430mu_wlan_w8.bin, fwuac430mu_otp_w8.bin and
           fwuac430mu_bdata_w8.bin from the AVM Windows driver (on Windows:
           C:\\Windows\\System32\\DriverStore\\FileRepository\\fwuac430mux_w8.inf_*)
  SDIO_FW  ath10k/QCA9377/hw1.0/firmware-sdio-5.bin (or .xz) from linux-firmware;
           only its container layout and the WMI/HTT/feature IEs are reused
  OUTDIR   receives firmware-usb-5.bin and board.bin
           (install to /lib/firmware/ath10k/QCA9377/avm/)

The AVM firmware uses the same SGMT segment format as the SDIO HL firmware of
the QCA9377, so it is repackaged into an ath10k IE container: the IE layout of
the SDIO container is kept, FW_VERSION/FW_IMAGE/OTP_IMAGE are replaced.
"""
import hashlib
import lzma
import struct
import sys
from pathlib import Path

MAGIC = b"QCA-ATH10K\0"
IE_VERSION, IE_FW_IMAGE, IE_OTP_IMAGE = 0, 3, 4
BOARD_SIZE = 8124


def parse(blob):
    if not blob.startswith(MAGIC):
        sys.exit("not an ath10k firmware container")
    off = (len(MAGIC) + 3) & ~3
    ies = []
    while off + 8 <= len(blob):
        ie_id, ie_len = struct.unpack_from("<II", blob, off)
        ies.append((ie_id, blob[off + 8:off + 8 + ie_len]))
        off += 8 + ((ie_len + 3) & ~3)
    return ies


def build(ies):
    out = bytearray(MAGIC.ljust((len(MAGIC) + 3) & ~3, b"\0"))
    for ie_id, data in ies:
        out += struct.pack("<II", ie_id, len(data)) + data
        out += b"\0" * (-len(data) & 3)
    return bytes(out)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    label = "WLAN.TF.1.1.1-AVM-11.3.4.0"
    if "--label" in sys.argv:
        label = sys.argv[sys.argv.index("--label") + 1]
        args.remove(label)
    if len(args) != 3:
        sys.exit(__doc__)
    avm, sdio, out = Path(args[0]), Path(args[1]), Path(args[2])

    for f in (sdio, avm / "fwuac430mu_wlan_w8.bin", avm / "fwuac430mu_otp_w8.bin",
              avm / "fwuac430mu_bdata_w8.bin"):
        if not f.is_file():
            sys.exit(f"missing: {f}")

    raw = sdio.read_bytes()
    sdio_fw = lzma.decompress(raw) if sdio.suffix == ".xz" else raw
    wlan = (avm / "fwuac430mu_wlan_w8.bin").read_bytes()
    otp = (avm / "fwuac430mu_otp_w8.bin").read_bytes()
    bdata = (avm / "fwuac430mu_bdata_w8.bin").read_bytes()
    for name, blob in (("wlan", wlan), ("otp", otp)):
        if not blob.startswith(b"SGMT"):
            sys.exit(f"fwuac430mu_{name}_w8.bin: no SGMT segment header")
    if len(bdata) != BOARD_SIZE:
        sys.exit(f"fwuac430mu_bdata_w8.bin: {len(bdata)} bytes, expected {BOARD_SIZE}")

    repl = {IE_VERSION: label.encode(), IE_FW_IMAGE: wlan, IE_OTP_IMAGE: otp}
    ies = parse(sdio_fw)
    missing = set(repl) - {i for i, _ in ies}
    if missing:
        sys.exit(f"SDIO container lacks IEs {sorted(missing)}")
    fw = build([(i, repl.get(i, d)) for i, d in ies])

    out.mkdir(parents=True, exist_ok=True)
    (out / "firmware-usb-5.bin").write_bytes(fw)
    (out / "board.bin").write_bytes(bdata)
    print(f"{out}/firmware-usb-5.bin  {len(fw)} bytes  sha256 {hashlib.sha256(fw).hexdigest()}")
    print(f"{out}/board.bin           {len(bdata)} bytes  sha256 {hashlib.sha256(bdata).hexdigest()}")


if __name__ == "__main__":
    main()
