#!/usr/bin/env bash
set -u

WS="$HOME/ros2_ws"
FAIL=0

ok()   { echo "[OK]   $1"; }
warn() { echo "[WARN] $1"; }
fail() { echo "[FAIL] $1"; FAIL=1; }

echo
echo "============================================================"
echo " AMR_FACTORY_NAVIGATOR — ENVIRONMENT CHECK"
echo "============================================================"
echo

# ------------------------------------------------------------
# Workspace
# ------------------------------------------------------------
if [ -d "$WS/src" ]; then
    ok "Workspace exists: $WS"
else
    fail "Workspace missing: $WS"
fi

# ------------------------------------------------------------
# ROS 2
# ------------------------------------------------------------
if [ -f /opt/ros/jazzy/setup.bash ]; then
    ok "ROS 2 Jazzy installation exists"
    set +u
    source /opt/ros/jazzy/setup.bash
    set -u
else
    fail "ROS 2 Jazzy installation missing"
fi

if [ "${ROS_DISTRO:-}" = "jazzy" ]; then
    ok "ROS_DISTRO=jazzy"
else
    fail "ROS_DISTRO is '${ROS_DISTRO:-unset}'"
fi

# ------------------------------------------------------------
# Project workspace
# ------------------------------------------------------------
if [ -f "$WS/install/setup.bash" ]; then
    set +u
    source "$WS/install/setup.bash"
    set -u
    ok "Workspace install space exists"
else
    warn "Workspace install/setup.bash missing"
fi

# ------------------------------------------------------------
# Project packages
# ------------------------------------------------------------
for pkg in \
    amr_bringup \
    amr_description \
    amr_hardware \
    amr_interfaces \
    amr_navigation
do
    if ros2 pkg prefix "$pkg" >/dev/null 2>&1; then
        ok "Project package: $pkg"
    else
        fail "Project package unavailable: $pkg"
    fi
done

# ------------------------------------------------------------
# Important ROS packages
# ------------------------------------------------------------
for pkg in \
    nav2_amcl \
    nav2_bringup \
    navigation2 \
    nav2_lifecycle_manager \
    slam_toolbox \
    controller_manager \
    diff_drive_controller \
    diagnostic_updater \
    rosbag2 \
    rosbag2_storage_mcap \
    mcap_vendor
do
    if ros2 pkg prefix "$pkg" >/dev/null 2>&1; then
        ok "Dependency: $pkg"
    else
        fail "Dependency missing: $pkg"
    fi
done

# ------------------------------------------------------------
# Gazebo
# ------------------------------------------------------------
if command -v gz >/dev/null 2>&1; then
    GZ_VERSION="$(gz sim --version 2>/dev/null || true)"
    echo "[INFO] Gazebo: $GZ_VERSION"

    if echo "$GZ_VERSION" | grep -q "8.11.0"; then
        ok "Gazebo Sim 8.11.0"
    else
        warn "Gazebo version differs from recorded known-good 8.11.0"
    fi
else
    fail "gz command unavailable"
fi

# ------------------------------------------------------------
# Important project files
# ------------------------------------------------------------
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
        ok "File: $f"
    else
        fail "Missing project file: $f"
    fi
done

# ------------------------------------------------------------
# MCAP
# ------------------------------------------------------------
if [ -f /opt/ros/jazzy/lib/librosbag2_storage_mcap.so ]; then
    ok "MCAP storage backend exists"
else
    fail "MCAP storage backend missing"
fi

if ros2 bag record --help 2>/dev/null | grep -q "mcap"; then
    ok "rosbag2 supports MCAP"
else
    fail "rosbag2 MCAP support unavailable"
fi

# ------------------------------------------------------------
# Runtime
# ------------------------------------------------------------
echo
echo "---------------- RUNTIME ----------------"

if ros2 node list >/dev/null 2>&1; then
    ok "ROS graph reachable"
    RUNTIME_AVAILABLE=1
else
    warn "ROS graph unavailable — runtime may simply be stopped"
    RUNTIME_AVAILABLE=0
fi

if [ "$RUNTIME_AVAILABLE" -eq 1 ] && command -v timeout >/dev/null 2>&1; then
    CONTROLLERS="$(timeout 5 ros2 control list_controllers 2>/dev/null || true)"

    if echo "$CONTROLLERS" | grep -q "diff_drive_controller.*active"; then
        ok "diff_drive_controller active"
    else
        warn "diff_drive_controller not active"
    fi

    if echo "$CONTROLLERS" | grep -q "joint_state_broadcaster.*active"; then
        ok "joint_state_broadcaster active"
    else
        warn "joint_state_broadcaster not active"
    fi
else
    warn "Controller runtime check skipped — runtime is not available"
fi

for node in planner_server controller_server bt_navigator; do
    STATE="$(ros2 lifecycle get "/$node" 2>/dev/null || true)"
    if echo "$STATE" | grep -q "active"; then
        ok "$node active"
    else
        warn "$node not active"
    fi
done

if ros2 lifecycle get /amcl 2>/dev/null | grep -q "active"; then
    ok "AMCL active"
else
    warn "AMCL not active"
fi

# ------------------------------------------------------------
# Topics
# ------------------------------------------------------------
for topic in \
    /scan \
    /tf \
    /tf_static \
    /amcl_pose \
    /diff_drive_controller/odom
do
    if ros2 topic list 2>/dev/null | grep -Fxq "$topic"; then
        ok "Topic exists: $topic"
    else
        warn "Topic unavailable: $topic"
    fi
done

echo
echo "============================================================"

if [ "$FAIL" -eq 0 ]; then
    echo " CHECK RESULT: PERSISTENT ENVIRONMENT OK"
    echo "============================================================"
    exit 0
else
    echo " CHECK RESULT: SOMETHING PERSISTENT IS MISSING"
    echo "============================================================"
    exit 1
fi
