#!/bin/bash
set -e

RULES_DIR="/home/pdiniz/Documentos/repos/install_hyperOS/mtkclient/Setup/Linux"

sudo cp "$RULES_DIR/50-android.rules" /etc/udev/rules.d/
sudo cp "$RULES_DIR/51-edl.rules" /etc/udev/rules.d/
sudo cp "$RULES_DIR/52-mtk.rules" /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger

echo "udev rules installed successfully."
