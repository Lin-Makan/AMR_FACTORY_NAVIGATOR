#!/usr/bin/env bash
set -u

WS="$HOME/ros2_ws"
MAP="$WS/src/amr_bringup/maps/factory_map.yaml"
PARAMS="$WS/src/amr_bringup/config/nav2_localization_params.yaml"

cd "$WS" || exit 1
set +u
source /opt/ros/jazzy/setup.bash || exit 1
source "$WS/install/setup.bash" || exit 1
set -u

echo
echo "============================================================"
echo " AMR_FACTORY_NAVIGATOR — LOCALIZATION"
echo "============================================================"
echo
echo "Starting localization only."
echo "Do NOT use this if localization is already running."
echo

ros2 launch nav2_bringup localization_launch.py \
  map:="$MAP" \
  params_file:="$PARAMS" \
  use_sim_time:=true
