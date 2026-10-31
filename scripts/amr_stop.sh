#!/usr/bin/env bash
set -u

echo
echo "============================================================"
echo " AMR_FACTORY_NAVIGATOR — SAFE STOP"
echo "============================================================"
echo
echo "This stops AMR project runtime processes."
echo "It does NOT delete project files."
echo

pkill -f "ros2 launch nav2_bringup navigation_launch.py" 2>/dev/null || true
pkill -f "ros2 launch nav2_bringup localization_launch.py" 2>/dev/null || true
pkill -f "ros2 launch amr_bringup simulation.launch.py" 2>/dev/null || true

echo "[INFO] Stop commands issued."
echo "[INFO] Verify with: ros2 node list"
echo
