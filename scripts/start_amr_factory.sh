#!/usr/bin/env bash

set -u

WS="$HOME/ros2_ws"
ROS_SETUP="/opt/ros/jazzy/setup.bash"
WS_SETUP="$WS/install/setup.bash"
NAV2_LAUNCH="$WS/src/amr_navigation/launch/navigation.launch.py"

echo ""
echo "======================================================"
echo "     AMR FACTORY NAVIGATOR - STARTUP"
echo "======================================================"
echo ""

# ------------------------------------------------------
# 1. ROS 2 environment
# ------------------------------------------------------

echo "[1/8] Loading ROS 2 Jazzy..."

if [ ! -f "$ROS_SETUP" ]; then
    echo "ERROR: ROS 2 Jazzy setup not found."
    exit 1
fi

source "$ROS_SETUP"

if [ -f "$WS_SETUP" ]; then
    source "$WS_SETUP"
fi

echo "ROS 2 Jazzy loaded."
echo ""

# ------------------------------------------------------
# 2. Required packages
# ------------------------------------------------------

echo "[2/8] Checking required ROS packages..."

PACKAGES=(
    ros-jazzy-nav2-map-server
    ros-jazzy-navigation2
    ros-jazzy-nav2-bringup
    ros-jazzy-slam-toolbox
    ros-jazzy-ros2-control
    ros-jazzy-ros2-controllers
    ros-jazzy-gz-ros2-control
)

MISSING=()

for PKG in "${PACKAGES[@]}"; do
    if dpkg -s "$PKG" >/dev/null 2>&1; then
        echo "  OK: $PKG"
    else
        echo "  MISSING: $PKG"
        MISSING+=("$PKG")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo ""
    echo "Installing missing packages..."
    sudo apt update
    sudo apt install -y "${MISSING[@]}"
else
    echo "All required packages are installed."
fi

echo ""

# ------------------------------------------------------
# 3. Verify Nav2
# ------------------------------------------------------

echo "[3/8] Verifying Nav2..."

source "$ROS_SETUP"

if ! ros2 pkg prefix nav2_map_server >/dev/null 2>&1; then
    echo "ERROR: nav2_map_server is still unavailable."
    echo "Try opening a new terminal and running this script again."
    exit 1
fi

if ! ros2 pkg prefix nav2_bringup >/dev/null 2>&1; then
    echo "ERROR: nav2_bringup is unavailable."
    exit 1
fi

echo "Nav2 is available."
echo ""

# ------------------------------------------------------
# 4. Build workspace
# ------------------------------------------------------

echo "[4/8] Building AMR workspace..."

cd "$WS"

colcon build --symlink-install \
    --packages-select \
    amr_interfaces \
    amr_description \
    amr_hardware \
    amr_bringup \
    amr_navigation

if [ $? -ne 0 ]; then
    echo ""
    echo "ERROR: Workspace build failed."
    exit 1
fi

source "$WS_SETUP"

echo "Workspace build successful."
echo ""

# ------------------------------------------------------
# 5. Check navigation launch file
# ------------------------------------------------------

echo "[5/8] Checking Nav2 launch file..."

if [ ! -f "$NAV2_LAUNCH" ]; then
    echo "ERROR: Navigation launch file not found:"
    echo "$NAV2_LAUNCH"
    exit 1
fi

echo "Navigation launch file found."
echo ""

# ------------------------------------------------------
# 6. Start Gazebo
# ------------------------------------------------------

echo "[6/8] Starting Gazebo simulation..."

export GZ_SIM_SYSTEM_PLUGIN_PATH="/opt/ros/jazzy/lib"
export GZ_GUI_PLUGIN_PATH="/opt/ros/jazzy/opt/gz_sim_vendor/lib/gz-sim-8/plugins/gui"

ros2 launch amr_bringup simulation.launch.py &
GAZEBO_PID=$!

echo "Gazebo launch PID: $GAZEBO_PID"
echo "Waiting for Gazebo/controller manager..."

# ------------------------------------------------------
# 7. Wait for controller manager
# ------------------------------------------------------

READY=0

for i in {1..60}; do

    if ! kill -0 "$GAZEBO_PID" 2>/dev/null; then
        echo ""
        echo "ERROR: Gazebo stopped unexpectedly."
        exit 1
    fi

    if ros2 service list 2>/dev/null | grep -q "/controller_manager/list_controllers"; then
        READY=1
        break
    fi

    sleep 1
done

if [ "$READY" -ne 1 ]; then
    echo ""
    echo "ERROR: Controller manager did not become available."
    echo "Gazebo is still running; inspect its output."
    exit 1
fi

echo "Controller manager is ready."
echo ""

# ------------------------------------------------------
# 8. Activate controllers
# ------------------------------------------------------

echo "[7/8] Activating controllers..."

ros2 control set_controller_state joint_state_broadcaster active

sleep 2

ros2 control set_controller_state diff_drive_controller active

sleep 3

echo ""
echo "Current controller state:"
ros2 control list_controllers

echo ""

# ------------------------------------------------------
# 9. Start Nav2
# ------------------------------------------------------

echo "[8/8] Starting Nav2..."
echo ""
echo "======================================================"
echo "        GAZEBO + CONTROLLERS + NAV2"
echo "                 ARE STARTING"
echo "======================================================"
echo ""

ros2 launch "$NAV2_LAUNCH"

# ------------------------------------------------------
# Cleanup when Nav2 exits
# ------------------------------------------------------

echo ""
echo "Nav2 has stopped."

if kill -0 "$GAZEBO_PID" 2>/dev/null; then
    echo "Stopping Gazebo..."
    kill "$GAZEBO_PID" 2>/dev/null
fi

wait "$GAZEBO_PID" 2>/dev/null

echo ""
echo "AMR Factory Navigator stopped."
