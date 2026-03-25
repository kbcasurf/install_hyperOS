#!/usr/bin/env bash
# flash_hyperos3.sh — Automated HyperOS 3 flasher for Redmi 13 (moon_global)
# Target ROM : OS3.0.6.0.WNTMIXM
# Method     : Fastboot (Linux)
#
# Usage: ./flash_hyperos3.sh [--skip-extract]
#   --skip-extract   Skip extraction if you already ran this before and
#                    just want to (re)flash from the existing work dir.

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROM_TGZ=""   # resolved at runtime by find_rom_file()
WORK_DIR="${SCRIPT_DIR}/hyperos3_extracted"
# Redmi 13 / POCO M6 Global reports "tides" at the bootloader level (hardware
# platform name) but is packaged as "moon"/"moon_global" in ROM filenames.
# Both are valid identifiers for the same device.
EXPECTED_CODENAMES=("tides" "moon" "moon_global")
FASTBOOT_TIMEOUT=60   # seconds to wait for device to appear in fastboot

# ─── Colours ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Prerequisite checks ─────────────────────────────────────────────────────
check_prerequisites() {
    info "Checking prerequisites…"

    for cmd in adb fastboot tar; do
        if ! command -v "$cmd" &>/dev/null; then
            die "'$cmd' is not installed. Install it with: sudo apt install android-tools-adb android-tools-fastboot tar"
        fi
    done
    ok "adb, fastboot, tar — all found."

    # Disk space: require at least 10 GB free in the script directory
    local free_kb
    free_kb=$(df -k "$SCRIPT_DIR" | awk 'NR==2 {print $4}')
    if (( free_kb < 10 * 1024 * 1024 )); then
        die "Less than 10 GB free in ${SCRIPT_DIR}. Free up space before flashing."
    fi
    ok "Disk space OK ($(( free_kb / 1024 / 1024 )) GB free)."
}

# ─── Locate the .tgz ROM file ─────────────────────────────────────────────────
find_rom_file() {
    # Accept any .tgz file in the script dir whose name contains the build ID
    local matches=()
    while IFS= read -r -d '' f; do
        matches+=("$f")
    done < <(find "$SCRIPT_DIR" -maxdepth 1 -name "*OS3.0.6.0.WNTMIXM*.tgz" -print0)

    if (( ${#matches[@]} == 0 )); then
        # Fallback: any .tgz present
        while IFS= read -r -d '' f; do
            matches+=("$f")
        done < <(find "$SCRIPT_DIR" -maxdepth 1 -name "*.tgz" -print0)
    fi

    if (( ${#matches[@]} == 0 )); then
        die "No .tgz ROM file found in:\n  ${SCRIPT_DIR}\nMake sure the download finished and the file is in the same folder as this script."
    fi

    if (( ${#matches[@]} > 1 )); then
        warn "Multiple .tgz files found — using the first one:"
        for f in "${matches[@]}"; do warn "  $f"; done
    fi

    ROM_TGZ="${matches[0]}"
    info "ROM file: $(basename "$ROM_TGZ") ($(du -sh "$ROM_TGZ" | cut -f1))"
}

# ─── ROM verification & extraction ───────────────────────────────────────────
extract_rom() {
    find_rom_file

    info "Verifying archive integrity (this may take a moment)…"
    if ! tar -tzf "$ROM_TGZ" &>/dev/null; then
        die "The .tgz archive appears to be corrupt or incomplete. Re-download it."
    fi
    ok "Archive integrity OK."

    info "Extracting ROM to: ${WORK_DIR}"
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    tar -xzf "$ROM_TGZ" -C "$WORK_DIR"
    ok "Extraction complete."
}

# ─── Locate flash script ──────────────────────────────────────────────────────
find_flash_script() {
    info "Looking for flash_all.sh inside extracted content…"

    local flash_script
    flash_script=$(find "$WORK_DIR" -name "flash_all.sh" -type f | head -1)

    if [[ -z "$flash_script" ]]; then
        warn "flash_all.sh not found in the extracted contents."
        warn "Directory listing of extracted files:"
        find "$WORK_DIR" -maxdepth 3 | head -40
        die "flash_all.sh not found — this archive does not look like a fastboot ROM.\n" \
            "A fastboot ROM must contain flash_all.sh and .img files.\n" \
            "Make sure you downloaded the *Fastboot* (.tgz) variant of OS3.0.6.0.WNTMIXM for moon_global."
    fi

    FLASH_SCRIPT_DIR="$(dirname "$flash_script")"
    ok "Found flash_all.sh at: ${flash_script}"

    # Sanity-check: make sure .img files are present
    local img_count
    img_count=$(find "$FLASH_SCRIPT_DIR" -name "*.img" | wc -l)
    if (( img_count < 5 )); then
        die "Only ${img_count} .img file(s) found — expected many more. ROM may be incomplete."
    fi
    ok "${img_count} partition images found."
}

# ─── Boot into fastboot ───────────────────────────────────────────────────────
boot_to_fastboot() {
    info "Attempting to reboot phone into fastboot via ADB…"

    # Check if any ADB device is online
    local adb_dev
    adb_dev=$(adb devices | grep -v "^List" | grep "device$" | awk '{print $1}' || true)

    if [[ -n "$adb_dev" ]]; then
        info "ADB device found (${adb_dev}). Sending reboot-to-bootloader command…"
        adb reboot bootloader
        info "Waiting for device to appear in fastboot…"
    else
        warn "No ADB device found. If your phone is not already in fastboot mode:"
        warn "  Power off → hold Power + Volume Down until you see the fastboot screen."
        warn "Then connect the USB cable and press ENTER to continue."
        read -rp "Press ENTER when the phone is in fastboot mode and USB is connected: "
    fi
}

# ─── Wait for fastboot device ─────────────────────────────────────────────────
wait_for_fastboot() {
    local elapsed=0
    while (( elapsed < FASTBOOT_TIMEOUT )); do
        if fastboot devices 2>/dev/null | grep -q "."; then
            ok "Fastboot device detected."
            return 0
        fi
        sleep 2
        (( elapsed += 2 ))
        printf "\r${CYAN}[INFO]${NC}  Waiting for fastboot… %ds" "$elapsed"
    done
    echo

    # Last-chance: try with sudo
    warn "Device not found under current user. Trying with sudo…"
    if sudo fastboot devices 2>/dev/null | grep -q "."; then
        ok "Device visible with sudo. You may need to add a udev rule for passwordless access."
        FASTBOOT_CMD="sudo fastboot"
        return 0
    fi

    die "No fastboot device detected after ${FASTBOOT_TIMEOUT}s.\n" \
        "Checklist:\n" \
        "  • Phone is in fastboot mode (bootloader screen visible)\n" \
        "  • USB cable is data-capable (not charge-only)\n" \
        "  • Try a different USB port\n" \
        "  • Run: lsusb | grep -i xiaomi"
}

# ─── Device identity check (the brick-prevention gate) ───────────────────────
verify_device() {
    info "Verifying device identity — this is the safety gate before any flashing."

    local product
    product=$(${FASTBOOT_CMD:-fastboot} getvar product 2>&1 | grep "^product" | awk '{print $2}' || true)

    if [[ -z "$product" ]]; then
        # Some firmware versions label it differently
        product=$(${FASTBOOT_CMD:-fastboot} getvar product 2>&1 | grep -i "product" | head -1 | sed 's/.*: *//' || true)
    fi

    info "Reported device product: '${product}'"

    local matched=false
    for name in "${EXPECTED_CODENAMES[@]}"; do
        if [[ "$product" == "$name" ]]; then
            matched=true
            break
        fi
    done

    if [[ "$matched" == false ]]; then
        die "DEVICE MISMATCH — expected one of (${EXPECTED_CODENAMES[*]}), got '${product}'.\n" \
            "This ROM is NOT for the connected device. Aborting to prevent a brick.\n" \
            "Disconnect this device and connect your Redmi 13 / POCO M6 Global."
    fi

    ok "Device confirmed: ${product} (Redmi 13 / POCO M6 Global). Safe to proceed."

    # Also show bootloader state for informational purposes
    local bl_state
    bl_state=$(${FASTBOOT_CMD:-fastboot} getvar unlocked 2>&1 | grep "^unlocked" | awk '{print $2}' || echo "unknown")
    if [[ "$bl_state" == "no" ]]; then
        die "Bootloader reports LOCKED. You must unlock it before flashing."
    fi
    ok "Bootloader is unlocked."
}

# ─── Final confirmation prompt ────────────────────────────────────────────────
confirm_flash() {
    echo
    echo -e "${BOLD}${RED}════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${RED}  WARNING — THIS WILL WIPE ALL DATA ON THE PHONE    ${NC}"
    echo -e "${BOLD}${RED}════════════════════════════════════════════════════${NC}"
    echo
    echo -e "  Device   : ${GREEN}Redmi 13 / POCO M6 Global (moon/tides)${NC}"
    echo -e "  ROM      : ${GREEN}OS3.0.6.0.WNTMIXM (HyperOS 3 / Android 16)${NC}"
    echo -e "  Script   : ${GREEN}${FLASH_SCRIPT_DIR}/flash_all.sh${NC}"
    echo
    echo -e "  • All personal data will be erased."
    echo -e "  • Do NOT unplug the USB cable during flashing (5–15 min)."
    echo -e "  • Do NOT press Ctrl+C once flashing starts."
    echo
    read -rp "Type YES (all caps) to confirm and start flashing: " answer
    if [[ "$answer" != "YES" ]]; then
        info "Flashing cancelled by user. Phone was NOT modified."
        exit 0
    fi
}

# ─── Flash ────────────────────────────────────────────────────────────────────
run_flash() {
    info "Making flash scripts executable…"
    chmod +x \
        "${FLASH_SCRIPT_DIR}/flash_all.sh" \
        "${FLASH_SCRIPT_DIR}/flash_all_lock.sh" \
        "${FLASH_SCRIPT_DIR}/flash_all_except_storage.sh" \
        2>/dev/null || true   # not all three scripts may exist — that's fine

    info "Starting flash — DO NOT unplug USB or interrupt this process."
    echo

    local log_file="${SCRIPT_DIR}/flash_$(date +%Y%m%d_%H%M%S).log"
    info "Full flash output is also saved to: ${log_file}"
    echo

    # Run flash_all.sh from its own directory (Xiaomi scripts use relative paths)
    pushd "$FLASH_SCRIPT_DIR" > /dev/null

    set +e   # Temporarily allow errors so we can catch and report them cleanly
    if [[ "${FASTBOOT_CMD:-fastboot}" == "sudo fastboot" ]]; then
        # flash_all.sh calls fastboot internally, so the whole script needs sudo
        sudo bash flash_all.sh 2>&1 | tee "$log_file"
    else
        bash flash_all.sh 2>&1 | tee "$log_file"
    fi
    local flash_exit=${PIPESTATUS[0]}
    set -e

    popd > /dev/null

    if (( flash_exit != 0 )); then
        echo
        die "flash_all.sh exited with error code ${flash_exit}.\n" \
            "Check the log at: ${log_file}\n" \
            "The phone may still be in fastboot mode — do not unplug.\n" \
            "Common causes:\n" \
            "  • USB cable disconnected during flash\n" \
            "  • Specific partition failed — check log for 'FAILED'\n" \
            "  • Try running: sudo bash ${FLASH_SCRIPT_DIR}/flash_all.sh"
    fi

    ok "Flashing completed successfully!"
}

# ─── Reboot ───────────────────────────────────────────────────────────────────
reboot_device() {
    info "Rebooting phone into system…"
    ${FASTBOOT_CMD:-fastboot} reboot
    echo
    ok "Done! The first boot may take 3–5 minutes — this is normal."
    ok "Log saved at: ${SCRIPT_DIR}/flash_*.log"
}

# ─── Cleanup on unexpected exit ───────────────────────────────────────────────
trap 'echo -e "\n${RED}[ERROR]${NC} Script interrupted unexpectedly. The phone may still be in fastboot mode — do NOT unplug until you verify its state." >&2' ERR

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo
    echo -e "${BOLD}HyperOS 3 Flasher — Redmi 13 (moon_global)${NC}"
    echo -e "ROM: OS3.0.6.0.WNTMIXM | Android 16"
    echo "────────────────────────────────────────────"
    echo

    FASTBOOT_CMD="fastboot"   # may be overridden to "sudo fastboot" by wait_for_fastboot

    check_prerequisites

    if [[ "${1:-}" != "--skip-extract" ]]; then
        extract_rom
        find_flash_script
    else
        info "--skip-extract: skipping extraction, looking for existing flash script…"
        find_flash_script
    fi

    boot_to_fastboot
    wait_for_fastboot
    verify_device
    confirm_flash
    run_flash
    reboot_device
}

main "$@"
