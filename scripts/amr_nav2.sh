#!/usr/bin/env bash
set -u

WS="$HOME/ros2_ws"
PARAMS="$WS/src/amr_bringup/config/nav2_localization_params.yaml"

cd "$WS" || exit 1
source /opt/ros/jazzy/setup.bash
source "$WS/install/setup.bash"

echo
echo "============================================================"
echo " AMR_FACTORY_NAVIGATOR — NAV2"
echo "============================================================"
echo
echo "IMPORTANT:"
echo "If Nav2 is already running, LEAVE IT RUNNING."
echo "Do not launch a second Nav2 stack."
echo

ros2 launch nav2_bringup navigation_launch.py \
  params_file:="$PARAMS" \
  use_sim_time:=true
