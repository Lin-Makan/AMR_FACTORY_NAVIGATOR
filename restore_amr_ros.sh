#!/bin/bash

set -e

echo "=========================================="
echo " AMR FACTORY NAVIGATOR ROS CHECK"
echo "=========================================="

source /opt/ros/jazzy/setup.bash

PKG_FILE="$HOME/ros2_ws/amr_ros_packages.txt"

if [ ! -f "$PKG_FILE" ]; then
    echo "ERROR: Package manifest missing:"
    echo "$PKG_FILE"
    exit 1
fi

MISSING=()

echo
echo "Checking required ROS packages..."
echo

while read -r PKG; do
    [ -z "$PKG" ] && continue

    if dpkg -s "$PKG" >/dev/null 2>&1; then
        echo "[OK]      $PKG"
    else
        echo "[MISSING] $PKG"
        MISSING+=("$PKG")
    fi
done < "$PKG_FILE"

echo

if [ ${#MISSING[@]} -eq 0 ]; then
    echo "=========================================="
    echo " ALL REQUIRED PACKAGES ARE PRESENT"
    echo "=========================================="
    exit 0
fi

echo "Missing packages:"
printf '  %s\n' "${MISSING[@]}"

echo
echo "Installing ONLY missing packages..."

sudo apt update
sudo apt install -y "${MISSING[@]}"

echo
echo "=========================================="
echo " RESTORE COMPLETE"
echo "=========================================="
