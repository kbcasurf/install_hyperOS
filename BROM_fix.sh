#!/usr/bin/env bash
# BROM_fix.sh — Fix USB driver conflicts for MTK BROM mode on Ubuntu
#
# Root causes solved:
#   1. cdc_acm kernel module grabs the BROM interface (0e8d:2000) within ~230ms.
#      modprobe -r alone is insufficient: the kernel auto-reloads cdc_acm via the
#      MODALIAS mechanism the moment a matching USB device appears. A modprobe.d
#      blacklist entry is required to permanently prevent auto-loading.
#   2. ModemManager probes every new USB serial device with AT commands,
#      causing EPIPE / EPROTO errors on both BROM and normal mode.
#
# What this script does:
#   - Creates /etc/modprobe.d/mtk-cdc-blacklist.conf (blacklist cdc_acm)
#   - Unloads cdc_acm from the running kernel
#   - Installs /etc/udev/rules.d/53-mtk-brom.rules:
#       * Unbinds cdc_acm from 0e8d:2000 on bind (belt-and-suspenders)
#       * Hides 0e8d:2000 and 0e8d:2046 from ModemManager
#   - Stops ModemManager for this session
#
# Usage:
#   ./BROM_fix.sh           — apply fixes and print connection procedure
#   ./BROM_fix.sh --restore — undo all changes and return system to normal

set -euo pipefail

RULES_FILE="/etc/udev/rules.d/53-mtk-brom.rules"
BLACKLIST_FILE="/etc/modprobe.d/mtk-cdc-blacklist.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MTKCLIENT_DIR="${SCRIPT_DIR}/mtkclient"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Sanity check ─────────────────────────────────────────────────────────────
check_prerequisites() {
    [[ "$(id -u)" -eq 0 ]] && die "Do NOT run as root. sudo is used internally where needed."
    [[ -d "$MTKCLIENT_DIR" ]] || die "mtkclient directory not found at: ${MTKCLIENT_DIR}"
}

# ─── udev rule ────────────────────────────────────────────────────────────────
install_udev_rule() {
    info "Installing udev rule: ${RULES_FILE}..."

    sudo tee "$RULES_FILE" > /dev/null << 'EOF'
# 53-mtk-brom.rules — MTK BROM USB conflict fix
#
# Problem: cdc_acm grabs 0e8d:2000 (MT65xx Preloader / BROM) in ~230ms,
# consuming the ~2.8s BROM window before mtkclient can claim the interface.
#
# Fix: unbind cdc_acm from this device the instant it attaches.
# ACTION=="bind" fires when the driver attaches — NOT "add" (which fires before
# the driver binds and would never match DRIVER=="cdc_acm").

# BROM mode — hide from ModemManager
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="0e8d", ATTRS{idProduct}=="2000", ENV{ID_MM_DEVICE_IGNORE}="1"

# BROM mode — unbind cdc_acm immediately on bind; %k resolves to interface name (e.g. 2-6:1.0)
ACTION=="bind", SUBSYSTEM=="usb", DRIVER=="cdc_acm", ATTRS{idVendor}=="0e8d", ATTRS{idProduct}=="2000", RUN+="/bin/sh -c 'echo -n %k > /sys/bus/usb/drivers/cdc_acm/unbind 2>/dev/null || true'"

# Normal mode (0e8d:2046) — hide from ModemManager to prevent EPIPE errors
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="0e8d", ATTRS{idProduct}=="2046", ENV{ID_MM_DEVICE_IGNORE}="1"
EOF

    sudo udevadm control --reload-rules
    sudo udevadm trigger
    ok "udev rule installed and reloaded."
}

# ─── ModemManager ─────────────────────────────────────────────────────────────
stop_modemmanager() {
    if systemctl is-active --quiet ModemManager 2>/dev/null; then
        info "Stopping ModemManager (this session only)..."
        sudo systemctl stop ModemManager
        ok "ModemManager stopped."
    else
        ok "ModemManager already inactive — skipping."
    fi
}

# ─── cdc_acm blacklist ────────────────────────────────────────────────────────
# modprobe -r alone is not enough: the kernel auto-reloads cdc_acm via MODALIAS
# the instant a CDC-class USB device appears. The blacklist entry prevents that.
blacklist_cdc_acm() {
    if [[ ! -f "$BLACKLIST_FILE" ]]; then
        info "Blacklisting cdc_acm (prevents kernel auto-reload on USB connect)..."
        echo "blacklist cdc_acm" | sudo tee "$BLACKLIST_FILE" > /dev/null
        ok "Blacklist entry created: ${BLACKLIST_FILE}"
    else
        ok "Blacklist entry already present: ${BLACKLIST_FILE}"
    fi
}

# ─── cdc_acm unload ───────────────────────────────────────────────────────────
unload_cdc_acm() {
    if lsmod | grep -q "^cdc_acm"; then
        local users
        users=$(lsmod | awk '/^cdc_acm/ {print $3}')
        if [[ "$users" -eq 0 ]]; then
            info "Unloading cdc_acm from running kernel (0 active users)..."
            sudo modprobe -r cdc_acm
            ok "cdc_acm unloaded."
        else
            warn "cdc_acm has ${users} active user(s) — another device is using it, cannot unload."
            warn "The modprobe.d blacklist + udev bind rule will block it on the next connection."
        fi
    else
        ok "cdc_acm is not loaded — nothing to do."
    fi
}

# ─── Restore ──────────────────────────────────────────────────────────────────
restore() {
    info "Restoring system to original state..."

    if [[ -f "$BLACKLIST_FILE" ]]; then
        sudo rm -f "$BLACKLIST_FILE"
        ok "Removed blacklist: ${BLACKLIST_FILE}"
    else
        ok "Blacklist file not present — nothing to remove."
    fi

    if [[ -f "$RULES_FILE" ]]; then
        sudo rm -f "$RULES_FILE"
        sudo udevadm control --reload-rules
        sudo udevadm trigger
        ok "Removed ${RULES_FILE} and reloaded udev rules."
    else
        ok "udev rule not present — nothing to remove."
    fi

    if ! lsmod | grep -q "^cdc_acm"; then
        info "Reloading cdc_acm..."
        sudo modprobe cdc_acm
        ok "cdc_acm loaded."
    else
        ok "cdc_acm already loaded."
    fi

    if ! systemctl is-active --quiet ModemManager 2>/dev/null; then
        info "Starting ModemManager..."
        sudo systemctl start ModemManager
        ok "ModemManager started."
    else
        ok "ModemManager already running."
    fi

    echo
    ok "System restored."
}

# ─── Next steps ───────────────────────────────────────────────────────────────
print_next_steps() {
    echo
    echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Environment ready — BROM connection procedure${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "  ${BOLD}Step 1 — Confirm the phone is fully powered off${NC}"
    echo -e "  The phone is in a boot loop. Wait for the charging screen to appear,"
    echo -e "  then hold ${BOLD}Power + Vol Down for 10s${NC} to force a hard power off."
    echo -e "  The screen must go completely dark (not just charging icon)."
    echo
    echo -e "  ${BOLD}Step 2 — Start mtkclient FIRST, THEN plug the phone${NC}"
    echo -e "  The BROM window is only ~2.8s. mtkclient must already be waiting."
    echo
    echo -e "  ${CYAN}  cd ${MTKCLIENT_DIR}${NC}"
    echo -e "  ${CYAN}  python3 mtk.py e nvdata${NC}     ${YELLOW}# erase nvdata partition${NC}"
    echo -e "  ${CYAN}  # or: python3 mtk.py e nvram${NC} ${YELLOW}# if nvdata alone doesn't fix it${NC}"
    echo
    echo -e "  Wait until you see: ${GREEN}\"Waiting for device...\"${NC}"
    echo
    echo -e "  ${BOLD}Step 3 — Enter true BROM mode${NC}"
    echo -e "  Hold ${BOLD}Volume Down + Volume Up simultaneously${NC}, plug the USB cable."
    echo -e "  (Vol Down alone triggers Preloader mode — security blocks DA upload there.)"
    echo -e "  Release buttons once mtkclient prints output."
    echo
    echo -e "  ${BOLD}Step 4 — After flashing, restore the system${NC}"
    echo -e "  ${CYAN}  $0 --restore${NC}"
    echo
    echo -e "${BOLD}══════════════════════════════════════════════════════════${NC}"
    echo
}

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
    echo
    echo -e "${BOLD}Changes applied:${NC}"
    echo -e "  ${GREEN}✓${NC} cdc_acm blacklisted: ${BLACKLIST_FILE} (prevents kernel auto-reload)"
    echo -e "  ${GREEN}✓${NC} cdc_acm unloaded from running kernel"
    echo -e "  ${GREEN}✓${NC} udev rule installed: ${RULES_FILE} (belt-and-suspenders unbind)"
    echo -e "  ${GREEN}✓${NC} ModemManager stopped (this session)"
    echo
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo
    echo -e "${BOLD}BROM Fix — MTK USB driver conflict resolver${NC}"
    echo "────────────────────────────────────────────"
    echo

    if [[ "${1:-}" == "--restore" ]]; then
        check_prerequisites
        restore
        return
    fi

    check_prerequisites
    blacklist_cdc_acm
    unload_cdc_acm
    install_udev_rule
    stop_modemmanager
    print_summary
    print_next_steps
}

main "$@"
