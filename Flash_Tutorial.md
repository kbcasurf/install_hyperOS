# Flash HyperOS 3 on Redmi 13 — Linux Guide

**Device:** Redmi 13 / POCO M6 Global (`moon_global`)
**Current version:** V816.0.8.0.UNTMIXM (HyperOS 1.0, Android 14)
**Target version:** OS3.0.6.0.WNTMIXM (HyperOS 3.0)
**Method:** Fastboot (Linux)

---

## Prerequisites

- Linux PC with `adb` and `fastboot` installed
- USB data cable (not charge-only)
- ~8 GB free disk space for ROM extraction
- Bootloader already unlocked (confirmed)

---

## Step 1 — Download the ROM

Download the `OS3.0.6.0.WNTMIXM` fastboot ROM (~8 GB `.tgz` file) from a trusted source such as `xiaomifirmwareupdater.com`.

Search for: **moon → Global → OS3.0.6.0.WNTMIXM → Fastboot**

---

## Step 2 — Extract the ROM

```bash
# Create a folder and extract
mkdir ~/hyperos3
tar -xzf ~/Downloads/moon_global_images_OS3.0.6.0.WNTMIXM*.tgz -C ~/hyperos3

# Check what's inside
ls ~/hyperos3/
```

You should see a folder with `.img` files and shell scripts including `flash_all.sh`.

---

## Step 3 — Boot Phone into Fastboot Mode

```bash
# Via ADB (if phone is connected and USB debugging is enabled):
adb reboot bootloader

# OR manually: power off → hold Power + Volume Down
```

---

## Step 4 — Verify Fastboot Sees the Device

```bash
fastboot devices
```

You should see your device serial number listed. If empty, check your USB connection and try a different port.

---

## Step 5 — Make Flash Scripts Executable

```bash
cd ~/hyperos3/

# Enter the extracted subfolder if needed:
cd $(ls -d */ | head -1)

chmod +x flash_all.sh flash_all_lock.sh flash_all_except_storage.sh
```

---

## Step 6 — Flash the ROM

```bash
# FULL WIPE (recommended — fixes NV data corruption):
./flash_all.sh
```

> `flash_all.sh` is Xiaomi's official script included in every fastboot ROM.
> It flashes all partitions including NVRAM, which resolves the "NV data is corrupted" error.

---

## Step 7 — Reboot

The flashing process takes **5–15 minutes**. Do **not** unplug the cable during this time.

When complete:

```bash
fastboot reboot
```

The first boot after flashing may take **3–5 minutes** — this is normal.

---

## Troubleshooting

### `flash_all.sh` is missing from the extracted folder

```bash
find ~/hyperos3/ -name "*.sh"
```

Use the path returned to locate and run the correct script.

### Fastboot doesn't detect the device

```bash
# Check if device is visible to the system at all:
lsusb | grep -i xiaomi

# If not visible, try:
sudo fastboot devices
```

### Permission denied on flash_all.sh

```bash
bash flash_all.sh
```

---

## Important Notes

- **Full data wipe** — all personal data will be erased. Back up anything important before flashing.
- **Do not interrupt** the flashing process — unplugging mid-flash can brick the device.
- **Skipping HyperOS 2** is safe via Fastboot — you are flashing a complete image, not an incremental OTA.
- This ROM includes an **Android version upgrade**: `U` prefix = Android 14 (current) → `W` prefix = Android 16 (target). Skipping Android 15 is safe via fastboot full-image flash.
- **Anti-rollback (ARB)** only applies to downgrades. Upgrading forward carries no ARB brick risk.
