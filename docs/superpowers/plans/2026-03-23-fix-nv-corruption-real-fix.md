# Fix NV Corruption — Real Fix via Slot B Boot + MTK META Mode

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover the Redmi 13 (moon_global / tides, MT6768 Helio G85) from "NV data is corrupted" boot loop after HyperOS 3 flash, using Slot B's old modem firmware and/or MTK META mode NV re-initialization.

**Why Task 6 (SP Flash Tool Format All + Download) does NOT work:** The HyperOS 3 scatter file (`MT6768_GL_Android_scatter.txt`) has `nvram`, `nvdata`, `nvcfg`, `protect1`, and `protect2` all set to `file_name: NONE` / `is_download: false`. SP Flash Tool "Format All + Download" erases those partitions but writes nothing back — identical to what the fastboot erases already did. No nvram.img exists anywhere in the official ROM package.

**Architecture:** Three progressive phases. Phase 1 exploits the A/B slot state: Slot A has HyperOS 3 (boot-loops), Slot B still has the pre-flash firmware — its older modem may tolerate blank nvram better and auto-regenerate NV. If Slot B boots, we can update via MiFlash which handles nvram migration correctly. If Slot B also fails, Phase 2 uses MTK META mode (hardware protocol, bypasses Android boot) to re-initialize nvram using the modem's built-in NV database via mtkclient (Linux) or Maui META Tool (Windows). Phase 3 covers IMEI restoration.

**Current Device State (as of last fastboot vars):**
- `current-slot: b` — device failovered here when slot A boot-looped
- `slot-unbootable:a: yes` — slot A explicitly abandoned by bootloader
- `slot-retry-count:a: 0` — slot A: zero retries left
- `slot-retry-count:b: 2` — slot B: still has retries
- `slot-successful:a: no`, `slot-successful:b: no` — neither slot ever reported success
- All NV partitions: `nvram`, `nvdata`, `nvcfg`, `protect1`, `protect2` — already erased/blank

**Tech Stack:** fastboot (Linux), mtkclient (Python, Linux), Maui META Tool (Windows — fallback), adb

---

## Before You Start

- Phone must be in **fastboot mode**: Power off → hold **Power + Volume Down** → connect USB.
- Confirm: `fastboot devices` (or `sudo fastboot devices`) shows the device.
- Run all `fastboot` commands from `~/Documents/repos/install_hyperOS/`.
- Keep USB connected throughout every task.

---

## Task 1: Try Slot B — Free Recovery Attempt

**Why:** Slot B still contains the modem firmware (`md1img`) from the ROM that was on the phone *before* the HyperOS 3 flash. Older MTK modem firmware versions are often more tolerant of blank nvram — they can detect an empty NV partition (all zeros) and regenerate a default NV database rather than throwing "NV data is corrupted." This costs nothing and takes 2 minutes.

- [ ] **Step 1: Confirm current state**

```bash
fastboot getvar current-slot 2>&1
fastboot getvar slot-unbootable:a 2>&1
fastboot getvar slot-unbootable:b 2>&1
```

Expected: `current-slot: b`, `slot-unbootable:a: yes`, `slot-unbootable:b: no`.

- [ ] **Step 2: Re-erase nvram before booting Slot B**

These partitions are already blank from previous fastboot erases. This is a precautionary confirmation — costs 10 seconds and ensures no partial write occurred since the last erase attempt.

```bash
fastboot erase nvram
fastboot erase nvdata
fastboot erase nvcfg
fastboot erase protect1
fastboot erase protect2
```

Each should print `Erasing '...' ... OKAY`.

- [ ] **Step 3: Explicitly set Slot B active and reboot**

> **Retry count warning:** `slot-retry-count:b: 2` — Slot B has only 2 retries left. Each failed boot consumes one. If both are consumed, the bootloader marks Slot B unbootable as well, leaving no bootable slot. If that happens, re-enter fastboot and run `fastboot set_active b` to reset the retry counter before trying again.

```bash
fastboot set_active b
fastboot reboot
```

- [ ] **Step 4: Observe boot result**

Wait up to 5 minutes (first boot after NV wipe is slow).

| Result | Next step |
|---|---|
| ✅ Boots to setup wizard or lock screen | Slot B works. See Task 2 (update properly). |
| ⚠️ Boots but shows no SIM / IMEI = 0 | Good enough. Go to Task 5 (IMEI restore). |
| ❌ "NV data is corrupted" / boot loop | Proceed to Task 3 (META mode). |
| ❌ Different error or stuck at MI logo | Proceed to Task 3 (META mode). |

---

## Task 2: If Slot B Boots — Update to HyperOS 3 Correctly

**Skip this task if Slot B did not boot.** This task only applies when you successfully booted into the old firmware on Slot B.

**Why:** Do NOT run `flash_all.sh` again. That's what caused the problem — it flashes a new `md1img` without migrating nvram. The correct update path is MiFlash (Windows) or a full `fastboot update` with a ROM that includes proper nvram migration scripts, or waiting for an OTA push.

- [ ] **Step 1: On Slot B, go to Settings → About Phone → Check for Updates**

If an OTA for HyperOS 3 appears and installs correctly, the system handles nvram migration. This is the safest path.

- [ ] **Step 2: If OTA is not available — use MiFlash on Windows**

MiFlash (Xiaomi's official flash tool) may use a different flash script than `flash_all.sh`.

**Before using MiFlash, verify it handles nvram differently:**
Open both `flash_all.bat` and `flash_all.sh` from the ROM package in a text editor. Check whether `nvram` appears in the flash commands. If both scripts skip nvram identically, MiFlash will repeat the same failure. In that case, skip MiFlash and go directly to Task 3/4.

If `flash_all.bat` does flash nvram:
Download: MiFlash from official Xiaomi/MIUI download pages.
ROM: Use the same `OS3.0.6.0.WNTMIXM` fastboot ROM package.
In MiFlash: select "clean all" (not "clean all and lock"), then flash.

- [ ] **Step 3: After HyperOS 3 flashes via MiFlash → reboot, verify**

The phone should boot into HyperOS 3 setup wizard. Verify IMEI via `*#06#` in the dialer. If IMEI is missing, proceed to Task 5.

---

## Task 3: BROM Erase via mtkclient — Linux

**Use if:** Slot B also boot-loops. **Scope:** mtkclient's role here is limited to BROM-level partition erase (more thorough than fastboot erase, bypasses the Android stack entirely). mtkclient cannot re-initialize nvram from the modem's NV database — that requires Maui META Tool in Task 4. Run Task 3 first to get the cleanest possible blank state, then Task 4 to write valid NV data into it.

> **BROM mode vs META mode — important distinction:**
> - **BROM mode** (Volume Down + USB): entered before the bootloader runs. mtkclient connects here.
> - **META mode** (Volume Up + USB): entered to run modem diagnostic protocol. Maui META Tool (Task 4) connects here.
> These are different hardware states. Wrong button = wrong mode = tool fails silently.

### Install mtkclient

- [ ] **Step 1: Clone and install mtkclient**

```bash
cd ~
git clone https://github.com/bkerler/mtkclient
cd mtkclient
pip3 install -r requirements.txt
pip3 install .
```

Install udev rules so the tool can access USB without sudo:

```bash
sudo usermod -a -G dialout $USER
sudo cp Setup/Linux/51-edl.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
# Log out and back in (or reboot) for group change to take effect
```

- [ ] **Step 2: Enter BROM mode and verify connectivity**

Power off the phone completely (hold power 10+ sec, wait for screen to go dark). Hold **Volume Down** and connect USB. The phone should show NO screen.

```bash
cd ~/mtkclient
python mtk.py printguid
```

Expected: prints device GUID and chipset info (`MT6768`).

> **If you see `DAA_SIG_VERIFY_FAILED`:** The kamakiri auth bypass is built into mtkclient for MT6768 — there is no separate payload file to run. A failure here means the exploit timing was off. Retry up to 3 times (power off between each). If it fails 3 times consistently, skip to Task 4 (Windows, Maui META Tool) — that tool has a more reliable auth implementation.

### Erase NV partitions via BROM

- [ ] **Step 3: Erase NV partitions cleanly via BROM**

These partitions are already blank from previous fastboot erases. This is a precautionary confirmation erase — it costs 30 seconds and ensures BROM-level zeroing rather than fastboot-level.

```bash
python mtk.py e nvram
python mtk.py e nvdata
python mtk.py e nvcfg
```

Each should print `Erasing nvram ... Done` (or similar). If a partition name is not found, skip it.

- [ ] **Step 4: Power off, re-enter fastboot mode**

After mtkclient completes, the phone is powered off. Re-enter fastboot:
Power off (confirm it's off) → hold **Power + Volume Down** → connect USB.

```bash
fastboot devices
```

Confirm the device appears.

- [ ] **Step 5: Set active slot to A and reboot**

> **Note:** Setting Slot A active here is tentative. Slot A is the HyperOS 3 slot that boot-loops. The BROM erase alone is unlikely to fix NV corruption (Task 4 does the actual re-initialization). If the phone boot-loops again after this step, re-enter fastboot (Power + Volume Down) and proceed to Task 4 — do not retry Slot A further without completing Task 4 first.

```bash
fastboot set_active a
fastboot reboot
```

- [ ] **Step 6: Observe result**

Wait 5 minutes. If HyperOS 3 boots → success. Proceed to Task 5 for IMEI.
If still looping → **re-enter fastboot** (Power + Volume Down, connect USB) → proceed to Task 4 (META mode NV re-initialization).

---

## Task 4: MTK META Mode NV Re-initialization — Windows (Maui META Tool / ModemMeta)

**Use if:** mtkclient on Linux fails (auth bypass unreliable on this unit) OR you have a Windows machine available. Maui META Tool has a more reliable implementation of the META protocol for NV restoration.

### Prerequisites

- Windows 10/11 machine
- MTK USB VCOM driver installed (from MTKdriverAutoInstaller)
- Maui META Tool (latest version from XDA: search "Maui META Tool MT6768") or MTK META Utility
- The phone in BROM/META mode

- [ ] **Step 1: Install MTK USB VCOM driver on Windows**

Download `MTKdriverAutoInstaller.exe` from XDA or Hovatek. Run it, select install all drivers. Reboot Windows.

- [ ] **Step 2: Enter META mode on the phone**

Power off phone completely. Hold **Volume Up** and connect USB. The LED should be dim or off. Device Manager should show a new COM port (MTK USB Port or similar).

> **If no COM port appears with Volume Up:** Try Volume Down instead. If neither works, the device may require a UART-mode META entry via test point short — consult XDA for the moon/tides hardware test point location.

- [ ] **Step 3: Open Maui META Tool**

1. Set the COM port to the MTK port detected in Device Manager.
2. Click "Connect" — the tool negotiates META protocol with the modem.
3. On success, the tool shows device info and NV menu.

- [ ] **Step 4: Restore default NV / initialize NV**

In Maui META Tool:
1. Go to **NV** tab → **Restore Default NV** (or similar wording — tool versions vary).
2. When prompted for AP_DB / MD1_DB: these are embedded in the modem firmware on the phone. The tool reads them directly from the device; you typically do not need to supply them externally.
3. Confirm the operation. The tool writes a valid NV structure to nvram matched to the installed `md1img`.

- [ ] **Step 5: Write your IMEI while in META mode**

Before disconnecting, write your IMEI (from phone box or `*#06#` record). In Maui META Tool: **NV → Write IMEI** → enter IMEI1 and IMEI2 → confirm.

- [ ] **Step 6: Disconnect and reboot**

Close META Tool, disconnect USB. Boot into fastboot:

```bash
fastboot set_active a
fastboot reboot
```

Wait 5 minutes. The phone should boot into HyperOS 3.

---

## Task 5: Restore IMEI (After Successful Boot)

**Do this only after the phone boots successfully.** Check `*#06#` in the dialer — if IMEI shows correctly, skip this task.

### Option A — mtkclient write_imei (Linux)

You need your original IMEI. Check: phone box label, Xiaomi account → purchased devices, or the receipt.

- [ ] **Step 1: Enter BROM mode**

Power off phone fully → hold Volume Down → connect USB.

- [ ] **Step 2: Verify write_imei command is available**

```bash
cd ~/mtkclient
python mtk.py --help | grep -i imei
```

If `write_imei` appears in the output, proceed. If not, skip to Option B or C.

- [ ] **Step 3: Write IMEI**

```bash
python mtk.py write_imei --imei1 <YOUR_IMEI1> --imei2 <YOUR_IMEI2>
```

Replace `<YOUR_IMEI1>` and `<YOUR_IMEI2>` with your actual IMEI values (15 digits each). IMEI2 is usually IMEI1 + 1 on dual-SIM devices.

> **Note:** Writing IMEI via mtkclient requires nvram to already be in a valid (initialized) state — meaning Task 4 must have fully succeeded before this step will work. If nvram is still blank, IMEI write will fail.

- [ ] **Step 4: Reboot and verify**

```bash
fastboot reboot
```

Dial `*#06#`. Both IMEI slots should show correct values.

### Option B — Maui META Tool IMEI write (Windows)

If mtkclient was already used in Task 4, the IMEI was written there. If not, repeat Task 4 Step 5 with Maui META Tool.

### Option C — Xiaomi Service Center

If neither tool works, take the phone + purchase box (with IMEI barcode) to a Xiaomi service center. They use official MTK tools and can restore IMEI.

---

## Quick Reference: Decision Tree

```
Phone in fastboot (current-slot: b)?
├── YES → Task 1: Try booting Slot B
│   ├── Slot B boots → Task 2: Update via MiFlash/OTA, Task 5 if IMEI missing
│   └── Slot B also loops → Task 3 (Linux) or Task 4 (Windows)
│       ├── META mode succeeds → Set active=a, reboot, Task 5 if IMEI missing
│       └── All META tools fail → Xiaomi service center (motherboard-level repair)
└── NO → Re-enter fastboot: Power off → Power+VolDown → connect USB
```

---

## Notes

- **Why not SP Flash Tool "Format All + Download"?** The scatter file proves `nvram` has `file_name: NONE` and `is_download: false`. "Format All" erases nvram (same as fastboot erase) but writes nothing back — no recovery occurs. Multiple community reports confirm this; some document `proinfo` loss (bootloader re-locks) as a side effect. Do not use Format All with this ROM package.
- **Why not flash nvram.img via SP Flash Tool "Download Only"?** No nvram.img exists in the official ROM package. Xiaomi intentionally excludes it to preserve IMEI during updates. There is no official source for a factory-blank nvram.img for this device.
- **SoC is MT6768 (Helio G85), NOT MT6835.** The original plan incorrectly listed MT6835. All tool versions, payloads, and DA files must match MT6768.
- **Slot A vs Slot B:** HyperOS 3 was flashed to Slot A. Slot A is currently marked unbootable. After any NV repair, use `fastboot set_active a` before rebooting to boot into HyperOS 3.
- **MTK auth bypass (kamakiri) for MT6768:** This is a hardware exploit that works on MT6768 but can be timing-sensitive. If it fails 3 times consecutively, switch to Windows + Maui META Tool.
