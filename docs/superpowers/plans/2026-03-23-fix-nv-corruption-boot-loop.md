# Fix NV Corruption Boot Loop — Redmi 13 HyperOS 3 Recovery Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore normal boot on a Redmi 13 (moon_global / tides) that boot-loops with "NV data is corrupted" after a successful fastboot flash of OS3.0.6.0.WNTMIXM.

**Architecture:** The flash completed without errors (slot set to `a`, reboot sent). The root cause is a `nvram` ↔ `md1img` version mismatch: `flash_all.sh` intentionally skips the `nvram` partition (to preserve IMEI), but the new MediaTek modem firmware (`md1img`) expects a different NV data layout than what the old `nvram` holds. We fix this progressively — from least destructive (erase NV, losing IMEI) to most complete (SP Flash Tool full scatter flash).

**Tech Stack:** fastboot (Linux), adb, mtkclient or SP Flash Tool (Windows/Linux), bash

---

## Before You Start

- Keep the USB cable plugged in throughout every task.
- Boot the phone into **fastboot mode**: Power off → hold **Power + Volume Down** until the fastboot screen appears, then connect USB.
- All `fastboot` commands below assume you run them from a terminal in `~/Documents/repos/install_hyperOS/`.
- If `fastboot devices` shows nothing, prefix every `fastboot` command with `sudo`.

---

## Task 1: Confirm Fastboot Connectivity and Gather State

**Goal:** Verify the phone is reachable and capture baseline diagnostics before touching anything.

- [ ] **Step 1: Boot into fastboot and check connectivity**

```bash
fastboot devices
```

Expected: a line like `XXXXXX  fastboot`. If blank, try `sudo fastboot devices`.

- [ ] **Step 2: Dump all fastboot variables to a file**

```bash
fastboot getvar all 2>&1 | tee fastboot_vars_$(date +%Y%m%d).txt
```

Key lines to look for in the output:
- `current-slot: a` (confirms slot A is active, matches the flash log)
- `unlocked: yes` (bootloader unlocked)
- `product: tides` (correct device)

- [ ] **Step 3: Check available partitions**

```bash
fastboot getvar partition-type:nvram 2>&1
fastboot getvar partition-type:nvdata 2>&1
fastboot getvar partition-type:nvcfg 2>&1
fastboot getvar partition-type:protect1 2>&1
fastboot getvar partition-type:protect2 2>&1
```

Note which partitions exist (not all MediaTek devices expose every one of these). Write down the results — you'll need them in the next tasks.

---

## Task 2: Erase NV Partitions (Recommended First Fix)

**Why:** The `nvram` partition holds IMEI + modem calibration data in a format tied to the previous `md1img` version. Erasing it lets the new modem firmware regenerate a clean NV structure on first boot. **Trade-off: IMEI will be lost** (shows as `000...0` or empty). It can be restored later via MTK META mode or a Xiaomi service center.

**Note:** Only erase the partitions confirmed to exist in Task 1.

- [ ] **Step 1: Erase nvram**

```bash
fastboot erase nvram
```

Expected: `Erasing 'nvram' ... OKAY`

- [ ] **Step 2: Erase nvdata (if it exists)**

```bash
fastboot erase nvdata
```

- [ ] **Step 3: Erase nvcfg (if it exists)**

```bash
fastboot erase nvcfg
```

- [ ] **Step 4: Erase protect1 and protect2 (if they exist)**

```bash
fastboot erase protect1
fastboot erase protect2
```

- [ ] **Step 5: Reboot and observe**

```bash
fastboot reboot
```

Watch the phone carefully:
- ✅ Success: Phone boots to HyperOS 3 setup wizard (may take 3–5 min first boot).
- ⚠️ Partial: Phone boots but shows no SIM / no IMEI → proceed to Task 5 to restore IMEI.
- ❌ Still loops → proceed to Task 3.

---

## Task 3: Re-Wipe Userdata and Cache (If Still Looping)

**Why:** Sometimes the flashed `userdata` has a filesystem inconsistency that causes init to fail before the full system mounts. A clean wipe forces `fsck` on first boot.

- [ ] **Step 1: Erase userdata and cache**

```bash
fastboot erase userdata
fastboot erase cache
```

- [ ] **Step 2: Reboot**

```bash
fastboot reboot
```

- If this resolves the boot loop → go to Task 5 if IMEI is missing.
- If still looping → proceed to Task 4.

---

## Task 4: Reflash System Partitions Only (Nuclear Reflash)

**Why:** If the NV erase and wipe didn't help, one of the system partitions flashed the first time may be in an inconsistent state. We reflash using `flash_all_except_storage.sh` which skips `userdata` (already wiped) but re-writes all OS partitions.

- [ ] **Step 1: Locate the flash script**

```bash
ls hyperos3_extracted/*/flash_all_except_storage.sh
```

- [ ] **Step 2: Reflash (run from the script's own directory)**

```bash
cd hyperos3_extracted/$(ls hyperos3_extracted/)/
bash flash_all_except_storage.sh 2>&1 | tee ../../reflash_$(date +%Y%m%d_%H%M%S).log
cd ../..
```

- [ ] **Step 3: After flash completes, erase NV partitions again**

Because the reflash will have written new `md1img` again, the `nvram` mismatch may recur. Erase NV partitions one more time before rebooting:

```bash
fastboot erase nvram
fastboot erase nvdata 2>/dev/null || true
fastboot erase nvcfg 2>/dev/null || true
```

- [ ] **Step 4: Set active slot explicitly and reboot**

```bash
fastboot --set-active=a
fastboot reboot
```

- If this resolves the loop → proceed to Task 5.
- If still looping → proceed to Task 5 (SP Flash Tool).

---

## Task 5: Restore IMEI via MTK META Mode (After Successful Boot)

**Do this only after the phone boots successfully.** Skip if your IMEI is intact (check with `*#06#` in the dialer).

### Option A — mtkclient (Linux, command line)

- [ ] **Step 1: Install mtkclient**

```bash
pip3 install mtkclient
# or clone from: https://github.com/bkerler/mtkclient
```

- [ ] **Step 2: Power off phone completely, then connect USB while holding Volume Down**

The phone enters MTK BROM (Boot ROM) mode — a hardware emergency mode that bypasses the bootloader. The LED should be dim or off.

- [ ] **Step 3: Read current NVRAM (to confirm connection)**

```bash
python3 -m mtkclient read_preloader
```

- [ ] **Step 4: Write your IMEI**

You need your original IMEI (found on the box, receipt, or under Settings → About Phone before flashing). Replace `IMEI1` and `IMEI2` with your actual values:

```bash
python3 -m mtkclient write_imei --imei1 <YOUR_IMEI1> --imei2 <YOUR_IMEI2>
```

### Option B — Xiaomi Service Center

If mtkclient does not work on your Linux setup, take the phone and your purchase box (with IMEI label) to a Xiaomi service center. They can restore IMEI via official MTK tools.

---

## Task 6: Last Resort — SP Flash Tool Full Scatter Flash

**Use only if Tasks 2–4 all failed.** This uses MediaTek's official flash tool to rewrite the entire device including `nvram` and all hidden partitions.

**Requires:** A Windows or Linux machine with SP Flash Tool installed, and the official scatter file from the ROM.

- [ ] **Step 1: Locate the MTK scatter file in the extracted ROM**

```bash
find hyperos3_extracted/ -name "*scatter*" -o -name "MT*.txt" 2>/dev/null
```

If found, it will be named something like `MT6835_Android_scatter.txt`.

- [ ] **Step 2: Download SP Flash Tool**

Download from the official MediaTek / Xiaomi support channels. Version must match MT6835 (the Dimensity 6100+ SoC).

- [ ] **Step 3: Flash with "Format All + Download"**

In SP Flash Tool:
1. Load the scatter file.
2. Select **Download** mode → choose **Format All + Download**.
3. Power off the phone, connect USB (no boot button held).
4. SP Flash Tool will detect BROM and flash all partitions including `nvram`.

This is the most complete recovery. It will restore a factory NV state paired to the correct modem firmware.

---

## Quick-Reference Diagnosis Table

| Symptom | Most Likely Cause | Go To |
|---|---|---|
| Boot loop, "NV data corrupted" in recovery | nvram ↔ md1img mismatch | Task 2 |
| Boot loop, no recovery error | userdata filesystem issue | Task 3 |
| Phone boots, no SIM / IMEI = 0 | nvram was erased | Task 5 |
| Phone boots, everything works | Done ✅ | — |
| All tasks failed, still looping | Deep partition corruption | Task 6 |

---

## Notes

- The flash log (`flash_20260323_154809.log`) confirms the flash itself was clean — no `FAILED` lines, slot set to `a`, reboot issued. The problem is post-flash NV incompatibility, not a bad flash.
- The device is identified as `tides` (MediaTek Dimensity 6100+). Do **not** use Qualcomm-specific tools (QPST, QFIL, EDL loaders) — they will not work on this device.
- Erasing `nvram` will cause temporary loss of IMEI and mobile data calibration. The phone will still function on Wi-Fi. IMEI restoration is straightforward via Task 5.
