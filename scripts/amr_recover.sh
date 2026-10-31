#!/usr/bin/env bash
set -u

WS="$HOME/ros2_ws"

echo
echo "============================================================"
echo " AMR_FACTORY_NAVIGATOR — RECOVERY"
echo "============================================================"
echo
echo "RULE: CHECK → FIX ONLY WHAT IS MISSING → VERIFY AGAIN"
echo "No blind reinstall. No blind rebuild. No blind upgrade."
echo

cd "$WS" || exit 1

# Source ROS first.
if [ -f /opt/ros/jazzy/setup.bash ]; then
    set +u
source /opt/ros/jazzy/setup.bash
set -u
else
    echo "[FAIL] ROS 2 Jazzy is missing."
    echo "       Recovery cannot continue safely."
    exit 1
fi

# Source workspace if available.
if [ -f "$WS/install/setup.bash" ]; then
    set +u
source "$WS/install/setup.bash"
set -u
fi

echo "[1/4] Checking persistent project files..."
MISSING=0

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
    if [ -f "$WS/$f" ]; then
        echo "[OK] $f"
    else
        echo "[FAIL] Missing: $f"
        MISSING=1
    fi
done

if [ "$MISSING" -ne 0 ]; then
    echo
    echo "[STOP] A persistent project file is missing."
    echo "       Do NOT reinstall packages automatically."
    echo "       Restore the project file/source first."
    exit 2
fi

echo
echo "[2/4] Checking ROS dependencies..."

DEPS_OK=1

for pkg in \
    nav2_amcl \
    nav2_bringup \
    navigation2 \
    slam_toolbox \
    controller_manager \
    diff_drive_controller \
    diagnostic_updater \
    rosbag2 \
    rosbag2_storage_mcap \
    mcap_vendor
do
    if ros2 pkg prefix "$pkg" >/dev/null 2>&1; then
        echo "[OK] $pkg"
    else
        echo "[MISSING] $pkg"
        DEPS_OK=0
    fi
done

if [ "$DEPS_OK" -eq 0 ]; then
    echo
    echo "[FIX] Missing ROS dependencies detected."
    echo "[FIX] Installing ONLY the missing dependencies..."

    APT_PACKAGES=()

    ros2 pkg prefix nav2_amcl >/dev/null 2>&1 || APT_PACKAGES+=("ros-jazzy-nav2-amcl")
    ros2 pkg prefix nav2_bringup >/dev/null 2>&1 || APT_PACKAGES+=("ros-jazzy-nav2-bringup")
    ros2 pkg prefix navigation2 >/dev/null 2>&1 || APT_PACKAGES+=("ros-jazzy-navigation2")
    ros2 pkg prefix nav2_lifecycle_manager >/dev/null 2>&1 || APT_PACKAGES+=("ros-jazzy-nav2-lifecycle-manager")
    ros2 pkg prefix slam_toolbox >/dev/null 2>&1 || APT_PACKAGES+=("ros-jazzy-slam-toolbox")
    ros2 pkg prefix controller_manager >/dev/null 2>&1 || APT_PACKAGES+=("ros-jazzy-controller-manager")
    ros2 pkg prefix diff_drive_controller >/dev/null 2>&1 || APT_PACKAGES+=("ros-jazzy-diff-drive-controller")
    ros2 pkg prefix diagnostic_updater >/dev/null 2>&1 || APT_PACKAGES+=("ros-jazzy-diagnostic-updater")
    ros2 pkg prefix rosbag2 >/dev/null 2>&1 || APT_PACKAGES+=("ros-jazzy-rosbag2")
    ros2 pkg prefix rosbag2_storage_mcap >/dev/null 2>&1 || APT_PACKAGES+=("ros-jazzy-rosbag2-storage-mcap")
    ros2 pkg prefix mcap_vendor >/dev/null 2>&1 || APT_PACKAGES+=("ros-jazzy-mcap-vendor")

    if [ "${#APT_PACKAGES[@]}" -eq 0 ]; then
        echo "[INFO] No apt packages require installation."
    else
        echo "[INFO] Packages to install:"
        printf '  %s\n' "${APT_PACKAGES[@]}"

        sudo apt update
        sudo apt install -y "${APT_PACKAGES[@]}"
    fi

    echo
    echo "[VERIFY] Re-checking dependencies..."

    set +u
    source /opt/ros/jazzy/setup.bash
    source "$WS/install/setup.bash"
    set -u

    DEPS_OK=1

    for pkg in         nav2_amcl         nav2_bringup         navigation2         nav2_lifecycle_manager         slam_toolbox         controller_manager         diff_drive_controller         diagnostic_updater         rosbag2         rosbag2_storage_mcap         mcap_vendor
    do
        if ros2 pkg prefix "$pkg" >/dev/null 2>&1; then
            echo "[OK] $pkg"
        else
            echo "[FAIL] Dependency still missing: $pkg"
            DEPS_OK=0
        fi
    done

    if [ "$DEPS_OK" -ne 1 ]; then
        echo
        echo "[STOP] Dependency recovery did not complete."
        exit 3
    fi

    echo "[OK] All required dependencies recovered."
fi

echo
echo "[3/4] Checking known-good versions..."

if command -v gz >/dev/null 2>&1; then
    echo "[INFO] $(gz sim --version 2>/dev/null || true)"
fi

echo "[INFO] controller_manager:"
ros2 pkg prefix controller_manager >/dev/null 2>&1 && \
    dpkg-query -W -f='${Version}\n' ros-jazzy-controller-manager 2>/dev/null || true

echo "[INFO] diff_drive_controller:"
ros2 pkg prefix diff_drive_controller >/dev/null 2>&1 && \
    dpkg-query -W -f='${Version}\n' ros-jazzy-diff-drive-controller 2>/dev/null || true

echo "[INFO] nav2_bringup:"
dpkg-query -W -f='${Version}\n' ros-jazzy-nav2-bringup 2>/dev/null || true

echo "[INFO] slam_toolbox:"
dpkg-query -W -f='${Version}\n' ros-jazzy-slam-toolbox 2>/dev/null || true

echo
echo "[4/4] Runtime status..."

if ros2 node list >/dev/null 2>&1; then
    echo "[INFO] ROS graph is available."
else
    echo "[INFO] No active ROS runtime detected."
fi

echo
echo "============================================================"
echo " RECOVERY CHECK COMPLETE"
echo "============================================================"
echo
echo "Persistent project: VERIFIED"
echo "Dependencies:       VERIFIED"
echo "Runtime:            CHECKED"
echo
echo "If this was a Construct timeout:"
echo "  1. Run ./scripts/amr_start.sh"
echo "  2. CHECK CURRENT POSE"
echo "  3. VERIFY TF"
echo "  4. CHOOSE GOAL"
echo "  5. MOVE"
echo
