#!/usr/bin/env bash
# flash_hyperos1.sh — Recovery flasher: HyperOS 1 on Redmi 13 (moon_global)
# Target ROM : OS1.0.8.0.UNTMIXM (HyperOS 1.0 / Android 14)
# Method     : Fastboot (Linux)
# Purpose    : Downgrade from HyperOS 3 + fix NV data corruption / boot loop
#
# Usage: ./flash_hyperos1.sh [--skip-extract]
#   --skip-extract   Skip extraction if already extracted; re-flash from existing work dir.

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROM_FILE=""       # resolved at runtime by find_rom_file()
ROM_BUILD_ID="OS1.0.8.0.UNTMIXM"
WORK_DIR="${SCRIPT_DIR}/hyperos1_extracted"
EXPECTED_CODENAMES=("tides" "moon" "moon_global")
FASTBOOT_TIMEOUT=60   # seconds to wait for device in fastboot
FASTBOOT_CMD="fastboot"   # may be overridden to "sudo fastboot"

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

    for cmd in adb fastboot; do
        if ! command -v "$cmd" &>/dev/null; then
            die "'$cmd' not found. Install with: sudo apt install android-tools-adb android-tools-fastboot"
        fi
    done

    # tar and unzip — only need whichever matches the archive format
    if ! command -v tar &>/dev/null && ! command -v unzip &>/dev/null; then
        die "Neither 'tar' nor 'unzip' found. Install with: sudo apt install tar unzip"
    fi
    ok "Required tools found."

    local free_kb
    free_kb=$(df -k "$SCRIPT_DIR" | awk 'NR==2 {print $4}')
    if (( free_kb < 10 * 1024 * 1024 )); then
        die "Less than 10 GB free in ${SCRIPT_DIR}. Free up space before flashing."
    fi
    ok "Disk space OK ($(( free_kb / 1024 / 1024 )) GB free)."
}

# ─── Locate the ROM archive (.tgz or .zip) ───────────────────────────────────
find_rom_file() {
    info "Looking for ${ROM_BUILD_ID} ROM archive in: ${SCRIPT_DIR}"

    local matches=()

    # Prefer exact build-ID match (.tgz then .zip)
    while IFS= read -r -d '' f; do matches+=("$f"); done \
        < <(find "$SCRIPT_DIR" -maxdepth 1 \( -name "*${ROM_BUILD_ID}*.tgz" -o -name "*${ROM_BUILD_ID}*.zip" \) -print0 2>/dev/null)

    # Fallback: any .tgz/.zip in the folder (user may have renamed it)
    if (( ${#matches[@]} == 0 )); then
        warn "No file matching '${ROM_BUILD_ID}' found. Falling back to any .tgz/.zip…"
        while IFS= read -r -d '' f; do matches+=("$f"); done \
            < <(find "$SCRIPT_DIR" -maxdepth 1 \( -name "*.tgz" -o -name "*.zip" \) -print0 2>/dev/null)
    fi

    if (( ${#matches[@]} == 0 )); then
        die "No ROM archive found in ${SCRIPT_DIR}\n" \
            "Download the fastboot ROM for ${ROM_BUILD_ID} (moon_global) and place it\n" \
            "in the same folder as this script, then re-run."
    fi

    if (( ${#matches[@]} > 1 )); then
        warn "Multiple archives found — using the first one. Move the others away if wrong:"
        for f in "${matches[@]}"; do warn "  $f"; done
    fi

    ROM_FILE="${matches[0]}"
    info "ROM archive: $(basename "$ROM_FILE") ($(du -sh "$ROM_FILE" | cut -f1))"
}

# ─── Archive verification & extraction ───────────────────────────────────────
extract_rom() {
    find_rom_file

    info "Verifying archive integrity…"
    case "$ROM_FILE" in
        *.tgz|*.tar.gz)
            tar -tzf "$ROM_FILE" &>/dev/null || die "Archive appears corrupt or incomplete. Re-download it."
            ok "Archive integrity OK."
            info "Extracting to: ${WORK_DIR}"
            rm -rf "$WORK_DIR"
            mkdir -p "$WORK_DIR"
            tar -xzf "$ROM_FILE" -C "$WORK_DIR"
            ;;
        *.zip)
            unzip -t "$ROM_FILE" &>/dev/null || die "Archive appears corrupt or incomplete. Re-download it."
            ok "Archive integrity OK."
            info "Extracting to: ${WORK_DIR}"
            rm -rf "$WORK_DIR"
            mkdir -p "$WORK_DIR"
            unzip -q "$ROM_FILE" -d "$WORK_DIR"
            ;;
        *)
            die "Unsupported archive format: $ROM_FILE (expected .tgz or .zip)"
            ;;
    esac
    ok "Extraction complete."
}

# ─── Locate flash_all.sh inside extracted content ────────────────────────────
find_flash_script() {
    info "Locating flash_all.sh inside extracted content…"

    local flash_script
    flash_script=$(find "$WORK_DIR" -name "flash_all.sh" -type f | head -1)

    if [[ -z "$flash_script" ]]; then
        warn "flash_all.sh not found. Contents:"
        find "$WORK_DIR" -maxdepth 3 | head -40
        die "flash_all.sh missing — this does not look like a fastboot ROM.\n" \
            "Make sure you downloaded the *Fastboot* variant of ${ROM_BUILD_ID} for moon_global."
    fi

    FLASH_SCRIPT_DIR="$(dirname "$flash_script")"
    ok "Found flash_all.sh at: ${flash_script}"

    local img_count
    img_count=$(find "$FLASH_SCRIPT_DIR" -name "*.img" | wc -l)
    if (( img_count < 5 )); then
        die "Only ${img_count} .img file(s) found — expected many more. ROM may be incomplete."
    fi
    ok "${img_count} partition images found."
}

# ─── Boot into fastboot ───────────────────────────────────────────────────────
boot_to_fastboot() {
    info "Attempting to reach phone via ADB…"

    local adb_dev
    adb_dev=$(adb devices 2>/dev/null | grep -v "^List" | grep "device$" | awk '{print $1}' || true)

    if [[ -n "$adb_dev" ]]; then
        info "ADB device found (${adb_dev}). Sending reboot-to-bootloader…"
        adb reboot bootloader
        info "Waiting for fastboot…"
    else
        warn "No ADB device found (expected — phone is likely boot-looping or off)."
        echo
        echo -e "  ${BOLD}Manual steps:${NC}"
        echo -e "  1. Power off the phone completely (hold Power ≥ 10 sec)."
        echo -e "  2. Hold ${BOLD}Power + Volume Down${NC} simultaneously."
        echo -e "  3. Connect USB cable to this PC."
        echo -e "  4. You should see the fastboot / bootloader screen."
        echo
        read -rp "Press ENTER once the phone is in fastboot mode and USB is connected: "
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

    warn "Device not found. Trying with sudo…"
    if sudo fastboot devices 2>/dev/null | grep -q "."; then
        ok "Device visible with sudo."
        FASTBOOT_CMD="sudo fastboot"
        return 0
    fi

    die "No fastboot device detected after ${FASTBOOT_TIMEOUT}s.\n" \
        "Check:\n" \
        "  • Phone shows fastboot/bootloader screen\n" \
        "  • USB cable is data-capable (not charge-only)\n" \
        "  • Try a different USB port\n" \
        "  • Run: lsusb | grep -i xiaomi"
}

# ─── Device identity check ───────────────────────────────────────────────────
verify_device() {
    info "Verifying device identity — brick-prevention gate."

    local product
    product=$(${FASTBOOT_CMD} getvar product 2>&1 | grep -i "^product" | awk '{print $2}' || true)
    if [[ -z "$product" ]]; then
        product=$(${FASTBOOT_CMD} getvar product 2>&1 | grep -i "product" | head -1 | sed 's/.*: *//' || true)
    fi

    info "Device reports product: '${product}'"

    local matched=false
    for name in "${EXPECTED_CODENAMES[@]}"; do
        [[ "$product" == "$name" ]] && matched=true && break
    done

    if [[ "$matched" == false ]]; then
        die "DEVICE MISMATCH — got '${product}', expected one of: ${EXPECTED_CODENAMES[*]}\n" \
            "This ROM is NOT for the connected device. Aborting to prevent a brick."
    fi
    ok "Device confirmed: ${product} (Redmi 13 / POCO M6 Global)."

    local unlocked
    unlocked=$(${FASTBOOT_CMD} getvar unlocked 2>&1 | grep "^unlocked" | awk '{print $2}' || echo "unknown")
    if [[ "$unlocked" == "no" ]]; then
        die "Bootloader is LOCKED. Cannot flash. Unlock it first."
    fi
    ok "Bootloader is unlocked."

    # Show current slot state for reference
    info "Current slot state:"
    ${FASTBOOT_CMD} getvar current-slot 2>&1 | grep -i "slot" | head -4 || true
    ${FASTBOOT_CMD} getvar slot-unbootable:a 2>&1 | grep -i "unbootable" | head -2 || true
    ${FASTBOOT_CMD} getvar slot-unbootable:b 2>&1 | grep -i "unbootable" | head -2 || true
}

# ─── Final confirmation ───────────────────────────────────────────────────────
confirm_flash() {
    echo
    echo -e "${BOLD}${RED}══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${RED}  RECOVERY FLASH — ALL DATA ON THE PHONE WILL BE WIPED ${NC}"
    echo -e "${BOLD}${RED}══════════════════════════════════════════════════════${NC}"
    echo
    echo -e "  Device   : ${GREEN}Redmi 13 / POCO M6 Global (moon/tides)${NC}"
    echo -e "  ROM      : ${GREEN}${ROM_BUILD_ID} (HyperOS 1.0 / Android 14)${NC}"
    echo -e "  Script   : ${GREEN}${FLASH_SCRIPT_DIR}/flash_all.sh${NC}"
    echo
    echo -e "  This will:"
    echo -e "    • Flash all partitions including nvram/nvdata/nvcfg (fixes NV corruption)"
    echo -e "    • Downgrade from HyperOS 3 → HyperOS 1"
    echo -e "    • Wipe all user data (expected — phone is bricked anyway)"
    echo -e "    • Reset slot A as the active boot slot"
    echo
    echo -e "  ${YELLOW}Do NOT unplug USB during flashing (takes 5–15 min).${NC}"
    echo -e "  ${YELLOW}Do NOT press Ctrl+C once flashing begins.${NC}"
    echo
    read -rp "Type YES (all caps) to confirm and start flashing: " answer
    if [[ "$answer" != "YES" ]]; then
        info "Cancelled. Phone was NOT modified."
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
        2>/dev/null || true

    local log_file="${SCRIPT_DIR}/flash_$(date +%Y%m%d_%H%M%S).log"
    info "Flash log: ${log_file}"
    info "Starting flash — DO NOT interrupt."
    echo

    pushd "$FLASH_SCRIPT_DIR" > /dev/null
    set +e
    if [[ "$FASTBOOT_CMD" == "sudo fastboot" ]]; then
        sudo bash flash_all.sh 2>&1 | tee "$log_file"
    else
        bash flash_all.sh 2>&1 | tee "$log_file"
    fi
    local flash_exit=${PIPESTATUS[0]}
    set -e
    popd > /dev/null

    if (( flash_exit != 0 )); then
        echo
        die "flash_all.sh exited with code ${flash_exit}.\n" \
            "Check: ${log_file}\n" \
            "Phone is likely still in fastboot — do NOT unplug.\n" \
            "Look for 'FAILED' lines in the log to identify the problem."
    fi

    ok "Flashing completed successfully!"
}

# ─── Reboot ───────────────────────────────────────────────────────────────────
reboot_device() {
    info "Rebooting into system…"
    ${FASTBOOT_CMD} reboot
    echo
    ok "Done! First boot takes 3–5 minutes — this is normal."
    ok "If IMEI is missing after boot, run the IMEI restore procedure."
    ok "Log saved at: ${SCRIPT_DIR}/flash_*.log"
}

# ─── Cleanup on unexpected exit ───────────────────────────────────────────────
trap 'echo -e "\n${RED}[ERROR]${NC} Script interrupted. Phone may still be in fastboot — do NOT unplug." >&2' ERR

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo
    echo -e "${BOLD}HyperOS 1 Recovery Flasher — Redmi 13 (moon_global)${NC}"
    echo -e "ROM: ${ROM_BUILD_ID} | Android 14 | Recovery from HyperOS 3 boot loop"
    echo "──────────────────────────────────────────────────────"
    echo

    check_prerequisites

    if [[ "${1:-}" != "--skip-extract" ]]; then
        extract_rom
        find_flash_script
    else
        info "--skip-extract: using existing extraction…"
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
