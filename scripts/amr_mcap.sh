#!/usr/bin/env bash
set -u

WS="$HOME/ros2_ws"
OUT="$WS/recordings/amr_navigation_demo"

cd "$WS" || exit 1
source /opt/ros/jazzy/setup.bash
source "$WS/install/setup.bash"

mkdir -p "$WS/recordings"

echo
echo "============================================================"
echo " AMR_FACTORY_NAVIGATOR — MCAP RECORDING"
echo "============================================================"
echo
echo "Recording lightweight navigation evidence."
echo
echo "Stop recording with Ctrl+C."
echo

ros2 bag record -s mcap \
  -o "$OUT" \
  /scan \
  /tf \
  /tf_static \
  /map \
  /amcl_pose \
  /diff_drive_controller/odom \
  /joint_states \
  /plan \
  /plan_smoothed \
  /clock
