#!/usr/bin/env bash
set -e

WS="$HOME/ros2_ws"
MAP="$WS/src/amr_bringup/maps/factory_map.yaml"
LOC_PARAMS="$WS/src/amr_bringup/config/nav2_localization_params.yaml"
NAV_PARAMS="$WS/src/amr_navigation/config/nav2_params.yaml"
LOGDIR="$WS/logs"

mkdir -p "$LOGDIR"

echo "=================================================="
echo " AMR FACTORY NAVIGATOR - FAST RECOVERY"
echo "=================================================="

set +u
source /opt/ros/jazzy/setup.bash
source "$WS/install/setup.bash"
set -u

export GZ_SIM_SYSTEM_PLUGIN_PATH=/opt/ros/jazzy/lib

echo
echo "===== 1. CHECK WORKSPACE ====="

for path in \
  "$WS/src/amr_bringup" \
  "$WS/src/amr_navigation" \
  "$WS/src/amr_description" \
  "$WS/src/amr_hardware" \
  "$WS/src/amr_interfaces" \
  "$MAP" \
  "$LOC_PARAMS" \
  "$NAV_PARAMS" \
  "$WS/src/amr_bringup/robots/robot.urdf" \
  "$WS/src/amr_bringup/config/controllers.yaml" \
  "$WS/src/amr_bringup/config/slam_toolbox.yaml"
do
  if [ -e "$path" ]; then
    echo "OK: $path"
  else
    echo "ERROR: Missing $path"
    exit 1
  fi
done

echo
echo "===== 2. CHECK CRITICAL PACKAGES ====="

REQUIRED_PKGS=(
  ros-jazzy-navigation2
  ros-jazzy-nav2-bringup
  ros-jazzy-nav2-amcl
  ros-jazzy-nav2-lifecycle-manager
  ros-jazzy-slam-toolbox
  ros-jazzy-controller-manager
  ros-jazzy-ros2-control
  ros-jazzy-ros2-controllers
  ros-jazzy-diff-drive-controller
  ros-jazzy-joint-state-broadcaster
  ros-jazzy-gz-ros2-control
  ros-jazzy-diagnostic-updater
  ros-jazzy-mcap-vendor
  ros-jazzy-rosbag2-storage-mcap
)

MISSING=()

for pkg in "${REQUIRED_PKGS[@]}"; do
  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    echo "OK: $pkg"
  else
    echo "MISSING: $pkg"
    MISSING+=("$pkg")
  fi
done

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo
  echo "Installing missing packages only..."
  sudo apt-get update
  sudo apt-get install -y "${MISSING[@]}"
else
  echo "All required packages are installed."
fi

echo
echo "===== 3. CHECK IMPORTANT VERSIONS ====="

dpkg-query -W -f='${Package} ${Version}\n' \
  ros-jazzy-controller-manager \
  ros-jazzy-diagnostic-updater \
  ros-jazzy-diff-drive-controller \
  ros-jazzy-joint-state-broadcaster \
  ros-jazzy-gz-ros2-control \
  ros-jazzy-navigation2 \
  ros-jazzy-nav2-bringup 2>/dev/null || true

echo
echo "===== 4. CHECK GAZEBO ====="

if ros2 topic list 2>/dev/null | grep -qx "/clock"; then
  echo "Gazebo/ROS simulation appears to be running."
  echo "KEEPING CURRENT GAZEBO RUNNING."
else
  echo "Gazebo is not detected."
  echo "Starting Gazebo..."

  nohup bash -c '
    set +u
    source /opt/ros/jazzy/setup.bash
    source ~/ros2_ws/install/setup.bash
    set -u
    export GZ_SIM_SYSTEM_PLUGIN_PATH=/opt/ros/jazzy/lib
    ros2 launch amr_bringup simulation.launch.py
  ' > "$LOGDIR/gazebo_recovery.log" 2>&1 &

  echo $! > "$LOGDIR/gazebo_recovery.pid"

  echo "Waiting for Gazebo..."
  for i in {1..30}; do
    if ros2 topic list 2>/dev/null | grep -qx "/clock"; then
      echo "Gazebo is ready."
      break
    fi
    sleep 1
  done
fi

echo
echo "===== 5. CHECK CONTROLLERS ====="

if ros2 control list_controllers 2>/dev/null | grep -q "diff_drive_controller.*active"; then
  echo "OK: diff_drive_controller active"
else
  echo "WARNING: diff_drive_controller is not confirmed active."
  echo "Checking controller manager..."

  ros2 control list_controllers 2>/dev/null || true

  if ros2 control list_controllers 2>/dev/null | grep -q "diff_drive_controller"; then
    echo "diff_drive_controller exists."
  fi

  if ros2 control list_controllers 2>/dev/null | grep -q "joint_state_broadcaster.*inactive"; then
    echo "Activating joint_state_broadcaster..."
    ros2 control set_controller_state joint_state_broadcaster active || true
  fi
fi

echo
echo "===== 6. CHECK LOCALIZATION ====="

if ros2 node list 2>/dev/null | grep -qx "/amcl"; then
  echo "AMCL already running."
  echo "KEEPING CURRENT LOCALIZATION RUNNING."
else
  echo "AMCL not detected. Starting localization..."

  nohup bash -c "
    set +u
    source /opt/ros/jazzy/setup.bash
    source $WS/install/setup.bash
    set -u

    ros2 launch nav2_bringup localization_launch.py \
      map:=$MAP \
      params_file:=$LOC_PARAMS \
      use_sim_time:=true
  " > "$LOGDIR/localization_recovery.log" 2>&1 &

  echo $! > "$LOGDIR/localization_recovery.pid"

  echo "Waiting for AMCL..."
  for i in {1..30}; do
    if ros2 node list 2>/dev/null | grep -qx "/amcl"; then
      echo "AMCL is running."
      break
    fi
    sleep 1
  done
fi

echo
echo "===== 7. SET AMCL INITIAL POSE ====="

ros2 topic pub --once /initialpose \
  geometry_msgs/msg/PoseWithCovarianceStamped \
  "{
    header: {frame_id: map},
    pose: {
      pose: {
        position: {x: 0.0, y: 0.0, z: 0.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      },
      covariance: [
        0.25,0,0,0,0,0,
        0,0.25,0,0,0,0,
        0,0,0,0,0,0,
        0,0,0,0,0,0.0685
      ]
    }
  }"

sleep 3

echo
echo "===== 8. VERIFY AMCL POSE ====="

ros2 topic echo /amcl_pose --once

echo
echo "===== 9. VERIFY MAP -> BASE_LINK ====="

timeout 5 ros2 run tf2_ros tf2_echo map base_link 2>&1 || true

echo
echo "===== 10. CHECK NAV2 ====="

if ros2 node list 2>/dev/null | grep -qx "/planner_server" && \
   ros2 node list 2>/dev/null | grep -qx "/controller_server" && \
   ros2 node list 2>/dev/null | grep -qx "/bt_navigator"; then

  echo "Nav2 nodes already running."
  echo "KEEPING CURRENT NAV2 RUNNING."
else
  echo "Nav2 is not fully detected. Starting Nav2..."

  nohup bash -c "
    set +u
    source /opt/ros/jazzy/setup.bash
    source $WS/install/setup.bash
    set -u

    ros2 launch "$WS/src/amr_navigation/launch/navigation.launch.py" \
      params_file:=$NAV_PARAMS
  " > "$LOGDIR/nav2_recovery.log" 2>&1 &

  echo $! > "$LOGDIR/nav2_recovery.pid"

  echo "Waiting for Nav2 nodes..."
  for i in {1..40}; do
    if ros2 node list 2>/dev/null | grep -qx "/planner_server" && \
       ros2 node list 2>/dev/null | grep -qx "/controller_server" && \
       ros2 node list 2>/dev/null | grep -qx "/bt_navigator"; then
      echo "Nav2 nodes detected."
      break
    fi
    sleep 1
  done
fi

echo
echo "===== FINAL SAFETY CHECK ====="

echo "NO MOVEMENT COMMAND HAS BEEN SENT."
echo "No navigation goal has been sent."

echo
echo "Current key nodes:"
ros2 node list 2>/dev/null | grep -E \
  '/(amcl|map_server|planner_server|controller_server|bt_navigator|robot_state_publisher)' \
  || true

echo
echo "Current controllers:"
ros2 control list_controllers 2>/dev/null || true

echo
echo "=================================================="
echo " RECOVERY CHECK COMPLETE"
echo "=================================================="
echo
echo "NEXT NAVIGATION RULE:"
echo "CHECK CURRENT POSE"
echo "-> VERIFY TF"
echo "-> CHOOSE VALID GOAL"
echo "-> MOVE"
echo
