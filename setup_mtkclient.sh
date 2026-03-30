#!/usr/bin/env bash
# setup_mtkclient.sh — Install mtkclient dependencies on Ubuntu 24.04 (no venv)
# Installs: system packages, Python deps (system-wide), udev rules, user groups.
#
# Usage: ./setup_mtkclient.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_DIR="${SCRIPT_DIR}/mtkclient/Setup/Linux"
REQUIREMENTS="${SCRIPT_DIR}/mtkclient/requirements.txt"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ─── Sanity checks ────────────────────────────────────────────────────────────
check_prerequisites() {
    info "Checking prerequisites..."

    [[ "$(id -u)" -eq 0 ]] && die "Do NOT run this script as root. It will use sudo when needed."

    if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
        warn "This script targets Ubuntu 24.04. Proceeding anyway on non-Ubuntu system."
    fi

    [[ -f "$REQUIREMENTS" ]] || die "requirements.txt not found at: ${REQUIREMENTS}"
    [[ -d "$RULES_DIR" ]]    || die "udev rules not found at: ${RULES_DIR}"

    ok "Prerequisites OK."
}

# ─── System packages ──────────────────────────────────────────────────────────
install_system_packages() {
    info "Installing system packages..."

    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        python3 \
        python3-pip \
        python3-dev \
        build-essential \
        git \
        curl \
        libssl-dev \
        libusb-1.0-0 \
        libusb-1.0-0-dev \
        libfuse-dev \
        libxcb-cursor0 \
        libbz2-dev \
        liblz4-dev \
        liblzma-dev \
        libsqlite3-dev \
        libreadline-dev \
        libffi-dev \
        python3-tk \
        tk-dev \
        android-tools-adb \
        android-tools-fastboot

    ok "System packages installed."
}

# ─── Python dependencies ──────────────────────────────────────────────────────
install_python_packages() {
    info "Installing Python packages from requirements.txt..."

    # Ubuntu 24.04 enforces PEP 668 (externally managed env).
    # --break-system-packages is required for system-wide pip installs.
    pip3 install --break-system-packages -r "$REQUIREMENTS"

    # Install the mtkclient package itself so its modules are importable system-wide.
    pip3 install --break-system-packages "${SCRIPT_DIR}/mtkclient"

    ok "Python packages installed."
}

# ─── udev rules ───────────────────────────────────────────────────────────────
install_udev_rules() {
    info "Installing udev rules..."

    sudo cp "${RULES_DIR}/50-android.rules" /etc/udev/rules.d/
    sudo cp "${RULES_DIR}/51-edl.rules"     /etc/udev/rules.d/
    sudo cp "${RULES_DIR}/52-mtk.rules"     /etc/udev/rules.d/
    sudo udevadm control --reload-rules
    sudo udevadm trigger

    ok "udev rules installed."
}

# ─── User groups ──────────────────────────────────────────────────────────────
add_user_groups() {
    info "Adding ${USER} to dialout and plugdev groups..."

    sudo usermod -aG dialout "$USER"
    sudo usermod -aG plugdev "$USER"

    ok "User groups updated."
    warn "A reboot (or 'newgrp') is required for group changes to take effect."
}

# ─── qcaux blacklist (prevents conflicts on devices with vendor interface 0xFF) ──
blacklist_qcaux() {
    local blacklist_file="/etc/modprobe.d/blacklist.conf"
    if ! grep -q "blacklist qcaux" "$blacklist_file" 2>/dev/null; then
        info "Blacklisting qcaux kernel module..."
        echo "blacklist qcaux" | sudo tee -a "$blacklist_file" > /dev/null
        ok "qcaux blacklisted."
    else
        ok "qcaux already blacklisted — skipping."
    fi
}

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
    echo
    echo -e "${BOLD}══════════════════════════════════════════${NC}"
    echo -e "${BOLD}  mtkclient setup complete${NC}"
    echo -e "${BOLD}══════════════════════════════════════════${NC}"
    echo
    echo -e "  ${GREEN}✓${NC} System packages installed"
    echo -e "  ${GREEN}✓${NC} Python packages installed (system-wide)"
    echo -e "  ${GREEN}✓${NC} udev rules applied"
    echo -e "  ${GREEN}✓${NC} User added to dialout + plugdev"
    echo -e "  ${GREEN}✓${NC} qcaux blacklisted"
    echo
    echo -e "  ${YELLOW}Next step: reboot your machine${NC}"
    echo -e "  After reboot, run mtkclient from: ${SCRIPT_DIR}/mtkclient/"
    echo -e "  Example: python3 mtk.py --help"
    echo
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo
    echo -e "${BOLD}mtkclient Setup — Ubuntu 24.04 (no venv)${NC}"
    echo "──────────────────────────────────────────"
    echo

    check_prerequisites
    install_system_packages
    install_python_packages
    install_udev_rules
    add_user_groups
    blacklist_qcaux
    print_summary
}

main "$@"
