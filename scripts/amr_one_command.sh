#!/usr/bin/env bash
set +u
source /opt/ros/jazzy/setup.bash
source ~/ros2_ws/install/setup.bash
cd ~/ros2_ws || exit 1

fail() { echo "STOP: $1"; exit 1; }

echo "========== 1. LOCALIZATION CHECK =========="
ros2 lifecycle get /amcl | grep -q 'active' || fail "AMCL is not active"
ros2 lifecycle get /map_server | grep -q 'active' || fail "Map server is not active"

echo "Requesting a no-motion AMCL update..."
timeout 8 ros2 service call /request_nomotion_update \
  std_srvs/srv/Empty "{}" || fail "AMCL update service failed"

echo "Checking latest pose..."
timeout 6 ros2 topic echo /amcl_pose --once \
  > /tmp/amr_pose_check.txt || fail "No AMCL pose received"
grep -q 'frame_id: map' /tmp/amr_pose_check.txt \
  || fail "AMCL pose is not in map frame"
cat /tmp/amr_pose_check.txt

echo
echo "========== 2. COMPLETE TF CHAIN =========="
timeout 5 ros2 run tf2_ros tf2_echo map odom \
  > /tmp/amr_tf_map_odom.txt 2>&1
grep -q 'Translation:' /tmp/amr_tf_map_odom.txt \
  || fail "map -> odom TF unavailable"
timeout 5 ros2 run tf2_ros tf2_echo odom base_link \
  > /tmp/amr_tf_odom_base.txt 2>&1
grep -q 'Translation:' /tmp/amr_tf_odom_base.txt \
  || fail "odom -> base_link TF unavailable"
timeout 5 ros2 run tf2_ros tf2_echo base_link lidar_link \
  > /tmp/amr_tf_base_lidar.txt 2>&1
grep -q 'Translation:' /tmp/amr_tf_base_lidar.txt \
  || fail "base_link -> lidar_link TF unavailable"
echo "TF links resolved individually."

echo
echo "========== 3. SENSOR AND NAV2 AUDIT =========="
timeout 5 ros2 topic echo /scan --once \
  > /tmp/amr_scan_check.txt || fail "No LiDAR scan received"
ros2 topic info /scan --verbose
ros2 topic info /diff_drive_controller/odom --verbose

if ros2 node list | grep -Eq '^/(planner_server|controller_server|bt_navigator)$'; then
  echo "Nav2 nodes already exist; will not launch a duplicate."
else
  echo "Launching Nav2 once..."
  ros2 launch amr_navigation navigation.launch.py \
    > /tmp/amr_nav2_launch.log 2>&1 &
  NAV_PID=$!
  echo "$NAV_PID" > /tmp/amr_nav2_launch.pid
fi

echo "Waiting for Nav2 startup..."
sleep 8
ros2 node list | sort
ros2 action list -t
ros2 topic list | grep -E 'cmd_vel|costmap|plan|odom|amcl_pose' || true

if ! ros2 action list | grep -q 'navigate_to_pose'; then
  echo "STOP: NavigateToPose is not available. No goal sent; inspect /tmp/amr_nav2_launch.log"
  exit 1
fi

echo
echo "========== 4. NAVIGATION SAFETY GATE =========="
echo "Nav2 action exists, but no verified free goal coordinate has been supplied."
echo "No movement command will be sent automatically."
echo "Confirm a free goal in the factory map before running a navigation test."

echo
echo "========== 5. MCAP SAFETY GATE =========="
echo "No MCAP started: record only after a verified goal test."
echo "Checklist and logs are preserved in /tmp/amr_*."
