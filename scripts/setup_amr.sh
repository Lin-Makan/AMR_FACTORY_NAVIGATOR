#!/usr/bin/env bash

set -e

echo "=========================================="
echo " AMR_FACTORY_NAVIGATOR"
echo " ROS 2 Jazzy"
echo "=========================================="

source /opt/ros/jazzy/setup.bash
source ~/ros2_ws/install/setup.bash

export AMR_PROJECT=AMR_FACTORY_NAVIGATOR
export AMR_WS=/home/user/ros2_ws

# Required for gz_ros2_control
export GZ_SIM_SYSTEM_PLUGIN_PATH=/opt/ros/jazzy/lib

cd ~/ros2_ws

echo ""
echo "Environment ready."
echo "Workspace: $AMR_WS"
echo "ROS distro: $ROS_DISTRO"
echo ""
