#!/usr/bin/env bash

set -e

echo "=========================================="
echo " AMR_FACTORY_NAVIGATOR"
echo " Installing ROS 2 Jazzy dependencies"
echo "=========================================="

source /opt/ros/jazzy/setup.bash

sudo apt update

sudo apt install -y \
  ros-jazzy-ros-gz-sim \
  ros-jazzy-ros-gz-bridge \
  ros-jazzy-gz-ros2-control \
  ros-jazzy-ros2-control \
  ros-jazzy-ros2-controllers \
  ros-jazzy-controller-manager \
  ros-jazzy-diff-drive-controller \
  ros-jazzy-robot-state-publisher \
  ros-jazzy-xacro \
  ros-jazzy-rviz2 \
  ros-jazzy-tf2-tools \
  ros-jazzy-slam-toolbox

echo ""
echo "=========================================="
echo " Dependencies installed successfully"
echo "=========================================="

echo ""
echo "Checking important packages..."

for pkg in \
  slam_toolbox \
  controller_manager \
  diff_drive_controller \
  robot_state_publisher \
  ros_gz_sim \
  ros_gz_bridge
do
    if ros2 pkg list | grep -qx "$pkg"; then
        echo "  [OK] $pkg"
    else
        echo "  [MISSING] $pkg"
    fi
done

echo ""
echo "AMR dependency recovery complete."
