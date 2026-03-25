# Brick Fix — Redmi 13 NV Corruption (Windows)
**Device:** Redmi 13 — moon_global / tides — MT6768 Helio G85
**Problem:** "NV data is corrupted" boot loop after ROM flash
**Your blocker:** Can't enter BROM mode → SP Flash Tool can't detect phone

---

## Read this first — why BROM mode has been failing you

BROM (Boot ROM) mode and fastboot mode look similar but are completely different hardware states:

| Mode | Entry | USB protocol | Detection window |
|---|---|---|---|
| **Fastboot** | Power + Vol Down (while off) | High-level, tolerant | Unlimited |
| **BROM** | Phone off + connect USB | Raw SoC handshake | ~3 seconds |
| **META** | Vol Up + connect USB | Modem diagnostic | ~5 seconds |

The three most common reasons BROM fails when fastboot works:

1. **Wrong USB port** — BROM on MT6768 requires a USB 2.0 port. USB 3.0 ports (blue inside) fail almost every time. Use the black USB-A ports on the back of the PC, not front-panel ports.
2. **Wrong order** — You must click Download in SP Flash Tool *before* connecting the phone. If you connect first, the BROM window has already closed before SP Flash Tool starts listening.
3. **Phone not truly off** — A phone stuck in a boot loop is not fully off when you hold power briefly. You must hold power for 10–15 seconds until the screen is black *and* the LED is off, then wait 5 more seconds before connecting USB.

---

## What you need before starting

- [ ] Your two IMEI numbers (from the phone box label)
- [ ] Windows 10 or 11 PC
- [ ] USB cable — use a **different cable** than the one that had issues before. Borrow one if needed. Charge-only cables will not work.
- [ ] The ROM images folder (already on your Linux machine — copy instructions below)
- [ ] A USB 2.0 port (black, not blue)

### Copy the ROM images to Windows

The images are already extracted on your Linux machine at:
```
~/Documents/repos/install_hyperOS/hyperos1_extracted/moon_global_images_OS1.0.8.0.UNTMIXM_14.0/images/
```

Copy the entire `images/` folder to your Windows PC. Target path (no spaces):
```
C:\moon_images\
```

Confirm these two files are present after copying:
- `MT6768_GL_Android_scatter.txt`
- `md1img.img`

---

## Part 1 — Install MTK USB drivers on Windows

SP Flash Tool will not detect the phone without these drivers.

### Step 1.1 — Download MTK VCOM drivers

Search for **"MTK VCOM All-in-one Drivers"** on XDA Developers. The file is typically named `MTK_USB_All_v1.0.8.zip` or similar. Download from XDA only.

### Step 1.2 — Disable driver signature enforcement

Some MTK driver packages are unsigned. Disable enforcement before installing:

1. Hold **Shift** and click **Start → Restart**
2. Navigate: **Troubleshoot → Advanced Options → Startup Settings → Restart**
3. When the numbered menu appears, press **7** (Disable driver signature enforcement)
4. Windows restarts in permissive driver mode

### Step 1.3 — Install the drivers

Extract the ZIP. Right-click `setup.exe` → **Run as Administrator**. Let it install all driver variants.

### Step 1.4 — Verify (without phone connected yet)

Open **Device Manager** (Win + X → Device Manager). You will not see the phone yet. That's expected — you'll verify detection in Part 2.

---

## Part 2 — SP Flash Tool: Format All + Download

This zeros the nvram partition at the raw eMMC level, which fastboot cannot do because the bootloader blocks it.

### Step 2.1 — Download SP Flash Tool

Search for **"SP Flash Tool v5 Windows MT6768"** on XDA Developers. Version 5.2124 or any v5.x works for MT6768. Extract to:
```
C:\SPFlashTool\
```

### Step 2.2 — Launch as Administrator

Right-click `flash_tool.exe` → **Run as Administrator**. If SmartScreen warns you: More info → Run anyway.

The main window opens with an empty partition list.

### Step 2.3 — Load the scatter file

1. Click **Choose** next to the "Scatter-loading file" field
2. Navigate to `C:\moon_images\MT6768_GL_Android_scatter.txt`
3. Click **Open**

The partition list populates (~20 entries). You will notice `nvram`, `nvdata`, `nvcfg`, `protect1`, `protect2` appear **without file paths** — this is correct and expected. SP Flash Tool will zero them during "Format All" even without image files.

### Step 2.4 — Select "Format All + Download" mode

Find the dropdown near the Download button (it may say "Download Only" by default). Change it to:
```
Format All + Download
```

> **Why this specific mode:** "Download Only" skips partitions with no image file and leaves nvram untouched — this is why a previous attempt may have failed silently. "Format All + Download" first erases the entire eMMC chip sector-by-sector (including nvram), then writes all partitions that have image files. The zeroed nvram is what forces the modem to regenerate valid NV data on first boot.

### Step 2.5 — The critical sequence to get BROM detection

This is where most failures happen. Follow this order exactly:

1. **Confirm the phone is completely off.** Hold power for 15 seconds. Wait until the screen is black and all LEDs are off. Wait 5 more seconds.
2. **Plug the USB cable into a USB 2.0 port** (black port, rear of PC). Do NOT connect the phone yet.
3. **In SP Flash Tool, click the Download button** (green downward arrow, bottom left). The status bar shows:
   ```
   Waiting for DA to connect...
   ```
4. **Now connect the USB cable to the phone** (powered-off phone, other end already in PC).
5. Watch Device Manager (keep it open in background) — you should briefly see:
   ```
   MTK PreLoader USB VCOM (Android)
   ```
   and SP Flash Tool status changes to `Download DA...` then `Format Flash...`

> **If Device Manager shows "Unknown Device" or nothing:** The MTK VCOM driver is not active. Redo Step 1.2 (signature enforcement) and Step 1.3. Also try holding **Volume Down** while connecting USB — some MT6768 variants need this.

> **If SP Flash Tool shows "Waiting for DA..." for more than 10 seconds with nothing:** Disconnect USB, close SP Flash Tool entirely, reopen it, reload the scatter file, re-select Format All + Download, click Download again, then reconnect the phone. The tool must be in "waiting" state *before* the USB connects.

### Step 2.6 — Wait for completion

Do not touch anything. The progress bar fills through Format and Download phases.

- Total time: approximately 8–15 minutes
- Do not disconnect USB
- Do not press anything on the phone

**Success:** A green circle with checkmark appears. Status shows `Download OK`.

**If you see a red circle / error code:**
- `0x1A` or auth error: retry — the BROM timing was off, just try again
- `0xC0060001`: wrong scatter file — confirm you're using `MT6768_GL_Android_scatter.txt` (not a HyperOS 3 scatter)
- Any error: do NOT reboot the phone. Note the code and see the Troubleshooting section.

### Step 2.7 — First boot after SP Flash Tool

Disconnect USB after "Download OK". The phone reboots automatically (or press power once if it doesn't start within 30 seconds).

- First boot takes **5–8 minutes** — this is normal after a full eMMC format
- Expected result: HyperOS setup wizard (language selection screen)
- If you reach setup wizard: ✅ SP Flash Tool worked. Proceed to Part 3 to restore IMEI.
- If "NV data is corrupted" appears again: Proceed to Part 3 (Maui META Tool) — the modem needs active NV re-initialization, not just a blank partition.

---

## Part 3 — Maui META Tool: NV Re-initialization

Use this if:
- SP Flash Tool completed successfully but NV corruption persists, OR
- You want to attempt NV repair without SP Flash Tool (META mode is different from BROM)

**META mode uses Volume Up, not Volume Down. This is a completely different hardware path and may work even if BROM mode has been failing.**

### Step 3.1 — Prerequisites for META mode

- MTK VCOM drivers already installed (Part 1)
- Phone must be **completely powered off** (15-second power hold, wait for LED off)

### Step 3.2 — Download Maui META Tool

Search for **"Maui META Tool MT6768"** or **"MTK META Utility"** on XDA Developers. The typical filename is `Maui_META_Tool_vX.X.zip` or `META_3D_LNX.zip`. Extract to:
```
C:\MauiMETA\
```

### Step 3.3 — Enter META mode on the phone

This is the step where the procedure differs from everything you've tried before:

1. Power off completely (hold power 15 sec, confirm LED is off, wait 5 more seconds)
2. Hold **Volume Up**
3. While holding Volume Up, connect USB to the PC (USB 2.0 port)
4. Keep holding Volume Up for 5 seconds, then release
5. The phone screen will be **black or blank** — this is correct. Do not expect a fastboot screen.
6. In Device Manager, look for a new COM port:
   ```
   MTK USB Modem Port (COM3)
   ```
   (the number may differ)

> **If no COM port appears:** Try the sequence again — timing matters. The USB must be connected while Volume Up is held from the very start. Also try holding Volume Up and pressing Volume Down briefly while holding it (on some MT6768 variants this triggers META).

### Step 3.4 — Connect with Maui META Tool

1. Right-click `META_tool.exe` → **Run as Administrator**
2. Select the COM port that appeared in Device Manager (e.g. COM3)
3. Set baudrate to `115200`
4. Click **Connect**
5. Status changes to `Connected` — the tool shows device info

### Step 3.5 — Restore default NV

This writes a valid NV structure matched to the modem firmware (`md1img`) already on the phone:

1. Navigate to: **NV** tab → **Restore Default NV** (exact label varies by version — also look for "Initialize NV", "Default NV", or "Reset NV")
2. When asked for AP_DB / MD1_DB files: these are embedded in the modem firmware already on the phone. The tool reads them directly from the device. You do not need to supply external files.
3. Confirm the operation
4. Wait for completion (1–3 minutes)

### Step 3.6 — Write IMEI while still connected

Do this before disconnecting — it's much easier now while you're already in META mode:

1. Navigate to: **NV → IMEI** (or **Engineer Mode → RF → IMEI**)
2. Enter your **IMEI 1** (15 digits from the box label)
3. Enter your **IMEI 2** (15 digits — usually printed below IMEI 1 on the box)
4. Click **Write** / **Send**
5. Confirm success message

### Step 3.7 — Reboot and verify

1. Close Maui META Tool
2. Disconnect USB
3. Boot the phone normally (press power button)
4. First boot: 5–8 minutes
5. After reaching setup wizard: open the Phone app, dial `*#06#`
6. Both IMEI slots should show your correct 15-digit numbers

---

## Part 4 — IMEI restoration (if you skipped Step 3.6)

If the phone booted but IMEI shows as `000000000000000` or blank:

### Option A — mtkclient on Linux (BROM mode required)

```bash
cd ~
git clone https://github.com/bkerler/mtkclient
cd mtkclient
pip3 install -r requirements.txt

# Add udev rules
sudo cp Setup/Linux/51-edl.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo usermod -a -G dialout $USER
# Log out and back in

# Enter BROM mode: power off → hold Vol Down → connect USB
python mtk.py write_imei --imei1 YOUR_IMEI1 --imei2 YOUR_IMEI2
```

### Option B — Maui META Tool (repeat Part 3, skip to Step 3.6)

If you already completed META mode once, repeat Part 3 and go straight to Step 3.6 to write IMEI.

### Option C — Xiaomi Service Center

If neither tool works: bring the phone and the box (with the IMEI label) to a Xiaomi authorized service center. They use official MTK tools and can restore IMEI from the hardware. This is free or low-cost if the phone is in warranty.

---

## Troubleshooting

### SP Flash Tool never detects the phone

Most likely cause: USB 3.0 port or wrong order.

Checklist:
- [ ] Using a USB 2.0 port (black, on the back of the PC — not front panel, not hub)
- [ ] SP Flash Tool was already showing "Waiting for DA..." **before** USB was connected
- [ ] Phone was completely off (held power 15+ sec, LED dark, waited 5 more sec)
- [ ] MTK VCOM driver installed with signature enforcement disabled
- [ ] Tried holding Volume Down while connecting (and also tried no button at all)
- [ ] Tried a completely different USB cable

If all of the above are checked and it still fails: the phone likely needs to be opened for the **test point short method** (forces BROM by shorting a PCB pad to ground). This requires partial disassembly and is a last resort before service center.

### SP Flash Tool connects but shows BROM auth error

Retry up to 5 times. The MT6768 kamakiri timing exploit occasionally fails. Each retry: disconnect USB, wait 5 seconds, reconnect. Do not close SP Flash Tool between retries.

### Phone boots but no signal / SIM not detected after NV restore

The NV was restored but IMEI is missing. Complete Part 4. Signal should return once IMEI is written.

### Maui META Tool shows "Cannot connect" or COM port disappears

The phone exited META mode. Redo Step 3.3. The most common mistake is connecting USB before holding Volume Up — the button must be held before the USB makes contact.

### Phone reaches setup wizard but boot-loops again on restart

This is a rare slot state issue. Before completing setup, connect USB and run:
```bash
fastboot set_active a
```
Then let the phone boot normally.

---

## Quick decision tree

```
SP Flash Tool → "Waiting for DA..." but no detection
  → Check USB port (must be 2.0), cable, driver, order → retry

SP Flash Tool → Detects phone, Format All + Download completes
  → Phone boots normally → DONE (check IMEI with *#06#)
  → Still "NV data is corrupted" → Go to Maui META Tool (Part 3)

Maui META Tool → META mode (Vol Up) not detected
  → Retry sequence, different cable/port
  → If still nothing → Xiaomi service center

Maui META Tool → Connects, Restore Default NV completes
  → Phone boots → DONE
```

---

## Device reference

| Item | Value |
|---|---|
| Codename | moon / tides |
| SoC | MT6768 (MediaTek Helio G85) |
| Scatter file | `MT6768_GL_Android_scatter.txt` |
| ROM build | OS1.0.8.0.UNTMIXM = V816.0.8.0.UNTMIXM (same ROM) |
| BROM entry | Power off → connect USB (no button) or hold Vol Down |
| META entry | Power off → hold Vol Up → connect USB |
| Fastboot entry | Power off → hold Power + Vol Down |
| SP Flash Tool | v5.x (MT6768 compatible) |
| USB requirement | USB 2.0 only for BROM/META |
