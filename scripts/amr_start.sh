#!/usr/bin/env bash
set -e

WS="$HOME/ros2_ws"
LOG="$WS/logs"
mkdir -p "$LOG"

echo
echo "============================================================"
echo " AMR_FACTORY_NAVIGATOR — QUICK START"
echo "============================================================"
echo " CHECK → REPAIR → GAZEBO → CONTROLLERS → AMCL → NAV2 → CHECK"
echo

cd "$WS"

# ------------------------------------------------------------
# 1. SAFE ROS SOURCING
# ------------------------------------------------------------
set +u
source /opt/ros/jazzy/setup.bash
[ -f "$WS/install/setup.bash" ] && source "$WS/install/setup.bash"
set -u

export GZ_SIM_SYSTEM_PLUGIN_PATH=/opt/ros/jazzy/lib

# ------------------------------------------------------------
# 2. CHECK REQUIRED ROS PACKAGES
# ------------------------------------------------------------
echo "[1/7] Checking required packages..."

MISSING=()

check_pkg() {
    if ros2 pkg prefix "$1" >/dev/null 2>&1; then
        echo "[OK] $1"
    else
        echo "[MISSING] $1"
        MISSING+=("$2")
    fi
}

check_pkg ros_gz_sim ros-jazzy-ros-gz-sim
check_pkg ros_gz_bridge ros-jazzy-ros-gz-bridge
check_pkg gz_ros2_control ros-jazzy-gz-ros2-control
check_pkg ros2_control ros-jazzy-ros2-control
check_pkg controller_manager ros-jazzy-controller-manager
check_pkg diff_drive_controller ros-jazzy-diff-drive-controller
check_pkg joint_state_broadcaster ros-jazzy-joint-state-broadcaster
check_pkg robot_state_publisher ros-jazzy-robot-state-publisher
check_pkg nav2_amcl ros-jazzy-nav2-amcl
check_pkg nav2_bringup ros-jazzy-nav2-bringup
check_pkg navigation2 ros-jazzy-navigation2
check_pkg nav2_lifecycle_manager ros-jazzy-nav2-lifecycle-manager
check_pkg nav2_map_server ros-jazzy-nav2-map-server
check_pkg slam_toolbox ros-jazzy-slam-toolbox
check_pkg diagnostic_updater ros-jazzy-diagnostic-updater
check_pkg rosbag2 ros-jazzy-rosbag2
check_pkg rosbag2_storage_mcap ros-jazzy-rosbag2-storage-mcap
check_pkg mcap_vendor ros-jazzy-mcap-vendor

# ------------------------------------------------------------
# 3. REPAIR ONLY WHAT IS MISSING + DIAGNOSTIC VERSION
# ------------------------------------------------------------
echo
echo "[2/7] Repairing missing dependencies..."

if [ "${#MISSING[@]}" -gt 0 ]; then
    printf '%s\n' "${MISSING[@]}" | sort -u

    sudo apt update
    sudo apt install -y $(printf '%s\n' "${MISSING[@]}" | sort -u)
else
    echo "[OK] Required packages already installed."
fi

DIAG_VERSION="$(dpkg-query -W -f='${Version}' ros-jazzy-diagnostic-updater 2>/dev/null || true)"

if [[ "$DIAG_VERSION" != 4.2.7-* ]]; then
    echo "[REPAIR] diagnostic_updater is $DIAG_VERSION"
    echo "[REPAIR] Installing known-good 4.2.7 package..."
    sudo apt update
    sudo apt install -y ros-jazzy-diagnostic-updater
else
    echo "[OK] diagnostic_updater $DIAG_VERSION"
fi

# Re-source after any package repair.
set +u
source /opt/ros/jazzy/setup.bash
source "$WS/install/setup.bash"
set -u
export GZ_SIM_SYSTEM_PLUGIN_PATH=/opt/ros/jazzy/lib

# ------------------------------------------------------------
# 4. VERIFY PERSISTENT PROJECT
# ------------------------------------------------------------
echo
echo "[3/7] Checking project files..."

for f in \
    src/amr_bringup/robots/robot.urdf \
    src/amr_bringup/worlds/empty_world.sdf \
    src/amr_bringup/launch/simulation.launch.py \
    src/amr_bringup/config/controllers.yaml \
    src/amr_bringup/config/slam_toolbox.yaml \
    src/amr_bringup/config/nav2_localization_params.yaml \
    src/amr_bringup/maps/factory_map.pgm \
    src/amr_bringup/maps/factory_map.yaml \
    src/amr_navigation/launch/navigation.launch.py \
    src/amr_navigation/config/nav2_params.yaml
do
    [ -f "$WS/$f" ] && echo "[OK] $f" || {
        echo "[FAIL] Missing $f"
        exit 2
    }
done

# ------------------------------------------------------------
# 5. GAZEBO + ROS2 CONTROL
# ------------------------------------------------------------
echo
echo "[4/7] Checking Gazebo / ros2_control..."

if ros2 node list 2>/dev/null | grep -qx "/controller_manager"; then
    echo "[OK] Gazebo/ros2_control already running."
else
    echo "[START] Gazebo + ros2_control..."
    nohup bash -c '
        set +u
        source /opt/ros/jazzy/setup.bash
        source ~/ros2_ws/install/setup.bash
        set -u
        export GZ_SIM_SYSTEM_PLUGIN_PATH=/opt/ros/jazzy/lib
        ros2 launch amr_bringup simulation.launch.py
    ' > "$LOG/gazebo.log" 2>&1 &

    echo "[WAIT] Waiting for controller_manager..."

    for i in {1..30}; do
        if ros2 node list 2>/dev/null | grep -qx "/controller_manager"; then
            echo "[OK] controller_manager running."
            break
        fi
        sleep 1
    done
fi

if ! ros2 node list 2>/dev/null | grep -qx "/controller_manager"; then
    echo "[FAIL] controller_manager did not start."
    echo "See: $LOG/gazebo.log"
    exit 3
fi

# ------------------------------------------------------------
# 6. CONTROLLERS
# ------------------------------------------------------------
echo
echo "[5/7] Checking controllers..."

timeout 5 ros2 control list_controllers || true

if ! timeout 5 ros2 control list_controllers 2>/dev/null \
    | grep -q "joint_state_broadcaster.*active"; then
    echo "[START] Activating joint_state_broadcaster..."
    ros2 control set_controller_state joint_state_broadcaster active || true
fi

if ! timeout 5 ros2 control list_controllers 2>/dev/null \
    | grep -q "diff_drive_controller.*active"; then
    echo "[START] Activating diff_drive_controller..."
    ros2 control set_controller_state diff_drive_controller active || true
fi

echo
timeout 5 ros2 control list_controllers || true

# ------------------------------------------------------------
# 7. LOCALIZATION + NAV2
# ------------------------------------------------------------
echo
echo "[6/7] Checking localization..."

if ros2 node list 2>/dev/null | grep -qx "/amcl"; then
    echo "[OK] AMCL already running."
else
    echo "[START] Localization / AMCL..."

    nohup bash -c '
        set +u
        source /opt/ros/jazzy/setup.bash
        source ~/ros2_ws/install/setup.bash
        set -u
        ros2 launch nav2_bringup localization_launch.py \
          map:=/home/user/ros2_ws/src/amr_bringup/maps/factory_map.yaml \
          params_file:=/home/user/ros2_ws/src/amr_bringup/config/nav2_localization_params.yaml \
          use_sim_time:=true
    ' > "$LOG/localization.log" 2>&1 &

    echo "[WAIT] Waiting for AMCL..."

    for i in {1..30}; do
        if ros2 node list 2>/dev/null | grep -qx "/amcl"; then
            echo "[OK] AMCL running."
            break
        fi
        sleep 1
    done
fi

if ! ros2 node list 2>/dev/null | grep -qx "/amcl"; then
    echo "[FAIL] AMCL did not start."
    echo "See: $LOG/localization.log"
    exit 4
fi

echo
echo "[INITIAL POSE] Setting AMCL pose..."

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
        0,0,0,0,0,0,
        0,0,0,0,0,0.0685
      ]
    }
  }"

sleep 2

echo
echo "[START] Checking Nav2..."

if ros2 node list 2>/dev/null | grep -qx "/planner_server"; then
    echo "[OK] Nav2 already running."
else
    nohup bash -c '
        set +u
        source /opt/ros/jazzy/setup.bash
        source ~/ros2_ws/install/setup.bash
        set -u
        ros2 launch nav2_bringup navigation_launch.py \
          params_file:=/home/user/ros2_ws/src/amr_bringup/config/nav2_localization_params.yaml \
          use_sim_time:=true
    ' > "$LOG/nav2.log" 2>&1 &

    echo "[WAIT] Waiting for Nav2..."

    for i in {1..45}; do
        if ros2 node list 2>/dev/null | grep -qx "/planner_server"; then
            echo "[OK] planner_server running."
            break
        fi
        sleep 1
    done
fi

# ------------------------------------------------------------
# FINAL READINESS CHECK
# ------------------------------------------------------------
echo
echo "[7/7] FINAL READINESS CHECK"
echo "============================================================"

echo
echo "--- Lifecycle ---"
for node in amcl planner_server controller_server bt_navigator; do
    printf "%-20s " "$node:"
    timeout 5 ros2 lifecycle get "/$node" 2>/dev/null | tail -1 || echo "not available"
done

echo
echo "--- Controllers ---"
timeout 5 ros2 control list_controllers || true

echo
echo "--- Required topics ---"
for topic in /map /amcl_pose /scan /tf /tf_static /diff_drive_controller/odom; do
    if ros2 topic list 2>/dev/null | grep -Fxq "$topic"; then
        echo "[OK] $topic"
    else
        echo "[WARN] $topic"
    fi
done

echo
echo "--- AMCL POSE ---"
timeout 5 ros2 topic echo /amcl_pose --once || true

echo
echo "--- ODOM ---"
timeout 5 ros2 topic echo /diff_drive_controller/odom --once || true

echo
echo "--- MAP -> BASE_LINK TF ---"
timeout 5 ros2 run tf2_ros tf2_echo map base_link || true

echo
echo "============================================================"
echo " QUICK START COMPLETE"
echo "============================================================"
echo
echo "NO MOVEMENT GOAL WAS SENT."
echo
echo "Required workflow before movement:"
echo "CHECK CURRENT POSE → VERIFY TF → CHOOSE GOAL → MOVE"
echo
echo "Logs:"
echo "  $LOG/gazebo.log"
echo "  $LOG/localization.log"
echo "  $LOG/nav2.log"
echo
