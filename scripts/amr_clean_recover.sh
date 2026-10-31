#!/usr/bin/env bash
set -u

# ============================================================
# AMR_FACTORY_NAVIGATOR
# CLEAN RECOVERY / ERROR-AUDIT SHORTCUT
#
# Architecture:
#
# GAZEBO
#   |
# LOCALIZATION
#   |-- map_server
#   |-- AMCL
#   '-- lifecycle_manager_localization
#          |
#       map -> base_link
#          |
# NAVIGATION
#   |-- planner_server
#   |-- controller_server
#   |-- velocity_smoother
#   |-- collision_monitor
#   |-- bt_navigator
#   |-- behavior_server
#   |-- waypoint_follower
#   '-- lifecycle_manager_navigation
#
# IMPORTANT:
# - Never starts/stops Gazebo.
# - Never sends movement commands.
# - Never edits tmux.
# - Never edits project configuration.
# - Never starts Nav2 before localization passes.
# ============================================================

set -o pipefail

WS="$HOME/ros2_ws"
MAP="$WS/src/amr_bringup/maps/factory_map.yaml"
LOC_PARAMS="$WS/src/amr_bringup/config/nav2_localization_params.yaml"
NAV_PARAMS="$WS/src/amr_navigation/config/nav2_params.yaml"
NAV_LAUNCH="$WS/src/amr_navigation/launch/navigation.launch.py"
LOGDIR="$WS/logs/amr_clean_recover"

mkdir -p "$LOGDIR"

source /opt/ros/jazzy/setup.bash
source "$WS/install/setup.bash"

# Fast DDS SHM is intentionally disabled for the recovery-launched
# ROS 2 navigation/localization processes.
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export RMW_FASTRTPS_USE_SHM=0

echo
echo "============================================================"
echo " AMR FACTORY NAVIGATOR — CLEAN RECOVERY"
echo "============================================================"
echo

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

count_pattern() {
    pgrep -af "$1" 2>/dev/null | grep -v "$$" | wc -l
}

show_pattern() {
    pgrep -af "$1" 2>/dev/null | grep -v "$$" || true
}

stop_tree() {
    local parent="$1"

    if ! kill -0 "$parent" 2>/dev/null; then
        return
    fi

    echo "Stopping process tree rooted at PID $parent"

    # Children first, then parent.
    local children
    children=$(pgrep -P "$parent" 2>/dev/null || true)

    for child in $children; do
        stop_tree "$child"
    done

    kill -TERM "$parent" 2>/dev/null || true
}

stop_matching_launches() {
    local pattern="$1"

    while true; do
        local pids
        pids=$(pgrep -f "$pattern" 2>/dev/null || true)

        [ -z "$pids" ] && break

        for pid in $pids; do
            [ "$pid" = "$$" ] && continue
            stop_tree "$pid"
        done

        sleep 3

        pids=$(pgrep -f "$pattern" 2>/dev/null || true)
        [ -z "$pids" ] && break

        for pid in $pids; do
            [ "$pid" = "$$" ] && continue
            kill -KILL "$pid" 2>/dev/null || true
        done

        sleep 2
    done
}

localization_healthy() {
    ros2 lifecycle get /map_server 2>/dev/null | grep -q "active \[3\]" &&
    ros2 lifecycle get /amcl 2>/dev/null | grep -q "active \[3\]" &&
    ros2 node list --no-daemon 2>/dev/null | grep -qx "/amcl" &&
    ros2 node list --no-daemon 2>/dev/null | grep -qx "/map_server" &&
    ros2 node list --no-daemon 2>/dev/null | grep -qx "/lifecycle_manager_localization"
}

# ------------------------------------------------------------
# 1. Gazebo — CHECK ONLY
# ------------------------------------------------------------

echo "===== 1. GAZEBO CHECK ====="

if ros2 node list --no-daemon 2>/dev/null | grep -qx "/controller_manager"; then
    echo "PASS: controller_manager detected"
else
    echo "WARNING: controller_manager not detected"
    echo "Gazebo was NOT restarted by this script."
    echo "Start Gazebo manually before continuing."
    exit 20
fi

if ros2 node list --no-daemon 2>/dev/null | grep -qx "/diff_drive_controller"; then
    echo "PASS: diff_drive_controller detected"
else
    echo "WARNING: diff_drive_controller not detected"
    echo "Gazebo was NOT restarted by this script."
    exit 21
fi

echo "Gazebo is being left untouched."
echo

# ------------------------------------------------------------
# 2. Check localization process count
# ------------------------------------------------------------

echo "===== 2. LOCALIZATION PROCESS CHECK ====="

LOC_COUNT=$(count_pattern "ros2 launch nav2_bringup localization_launch.py")

echo "Localization launch count: $LOC_COUNT"

if [ "$LOC_COUNT" -gt 1 ]; then
    echo "ERROR: duplicate localization launches detected."
    show_pattern "ros2 launch nav2_bringup localization_launch.py"

    echo
    echo "Stopping duplicate localization stack..."
    stop_matching_launches "ros2 launch nav2_bringup localization_launch.py"

    LOC_COUNT=0
fi

# ------------------------------------------------------------
# 3. Preserve healthy localization
# ------------------------------------------------------------

echo
echo "===== 3. LOCALIZATION HEALTH CHECK ====="

if localization_healthy; then
    echo "PASS: localization is already healthy."
    echo "NO localization restart required."
else
    echo "Localization is NOT healthy."
    echo "A clean localization restart is required."

    echo
    echo "Stopping existing localization launch..."
    stop_matching_launches "ros2 launch nav2_bringup localization_launch.py"

    echo
    echo "Cleaning stale Fast-DDS SHM files..."

    find /dev/shm -maxdepth 1 -type f \
        \( -name 'fastrtps_port*_el' -o -name 'fastrtps_*_el' \) \
        -print -delete 2>/dev/null || true

    echo
    echo "Starting localization with Fast-DDS SHM disabled..."

    nohup bash -c "
        source /opt/ros/jazzy/setup.bash
        source '$WS/install/setup.bash'
        export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
        export RMW_FASTRTPS_USE_SHM=0

        ros2 launch nav2_bringup localization_launch.py \
          map:='$MAP' \
          params_file:='$LOC_PARAMS' \
          use_sim_time:=true
    " > "$LOGDIR/localization.log" 2>&1 &

    LOC_PID=$!

    echo "Localization launch PID: $LOC_PID"

    echo
    echo "Waiting for localization..."

    for i in $(seq 1 30); do
        sleep 2

        if localization_healthy; then
            echo "PASS: localization became healthy."
            break
        fi

        echo "  waiting... $i/30"
    done

    if ! localization_healthy; then
        echo
        echo "ERROR: localization failed to become healthy."
        echo
        echo "===== LOCALIZATION LOG ====="
        tail -100 "$LOGDIR/localization.log"
        exit 30
    fi
fi

# ------------------------------------------------------------
# 4. Localization verification
# ------------------------------------------------------------

echo
echo "===== 4. LOCALIZATION VERIFICATION ====="

echo "--- Nodes ---"
ros2 node list --no-daemon | grep -E '^/map_server$|^/amcl$|^/lifecycle_manager_localization$'

echo
echo "--- Lifecycle ---"
ros2 lifecycle get /map_server
ros2 lifecycle get /amcl

echo
echo "--- /map ---"
ros2 topic info /map | head -10

echo
echo "--- /amcl_pose ---"
ros2 topic info /amcl_pose | head -10

echo
echo "--- map -> base_link TF ---"
timeout 5 ros2 run tf2_ros tf2_echo map base_link 2>&1 | head -30 || true

echo

# ------------------------------------------------------------
# 5. Nav2 process duplication check
# ------------------------------------------------------------

echo "===== 5. NAV2 DUPLICATE CHECK ====="

NAV_COUNT=$(count_pattern "ros2 launch amr_navigation navigation.launch.py")

echo "Custom Nav2 launch count: $NAV_COUNT"

if [ "$NAV_COUNT" -gt 1 ]; then
    echo
    echo "ERROR: multiple custom Nav2 launches detected."
    show_pattern "ros2 launch amr_navigation navigation.launch.py"

    echo
    echo "Stopping all custom Nav2 launch processes..."
    stop_matching_launches "ros2 launch amr_navigation navigation.launch.py"

    NAV_COUNT=0
fi

# ------------------------------------------------------------
# 6. Nav2 health
# ------------------------------------------------------------

echo
echo "===== 6. NAV2 HEALTH ====="

NAV2_NODES=(
    "/planner_server"
    "/controller_server"
    "/velocity_smoother"
    "/collision_monitor"
    "/bt_navigator"
    "/behavior_server"
    "/waypoint_follower"
    "/lifecycle_manager_navigation"
)

NAV2_OK=1

for node in "${NAV2_NODES[@]}"; do
    if ros2 node list --no-daemon 2>/dev/null | grep -qx "$node"; then
        echo "FOUND: $node"
    else
        echo "MISSING: $node"
        NAV2_OK=0
    fi
done

echo

# ------------------------------------------------------------
# 7. Start Nav2 only if missing
# ------------------------------------------------------------

if [ "$NAV2_OK" -eq 1 ]; then
    echo "PASS: Nav2 nodes already exist."
    echo "NO Nav2 restart required."
else
    echo "Nav2 is not currently running."
    echo "Localization is healthy."
    echo "Starting the ONE custom Nav2 launch..."

    nohup bash -c "
        source /opt/ros/jazzy/setup.bash
        source '$WS/install/setup.bash'
        export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
        export RMW_FASTRTPS_USE_SHM=0

        ros2 launch '$NAV_LAUNCH' \
          params_file:='$NAV_PARAMS'
    " > "$LOGDIR/navigation.log" 2>&1 &

    NAV_PID=$!

    echo "Nav2 launch PID: $NAV_PID"

    echo
    echo "Waiting for Nav2..."

    for i in $(seq 1 30); do
        sleep 2

        MISSING=0

        for node in "${NAV2_NODES[@]}"; do
            if ! ros2 node list --no-daemon 2>/dev/null | grep -qx "$node"; then
                MISSING=1
            fi
        done

        if [ "$MISSING" -eq 0 ]; then
            echo "PASS: all Nav2 nodes detected."
            break
        fi

        echo "  waiting... $i/30"
    done
fi

# ------------------------------------------------------------
# 8. Final Nav2 lifecycle audit
# ------------------------------------------------------------

echo
echo "===== 7. NAV2 LIFECYCLE AUDIT ====="

for node in \
    /planner_server \
    /controller_server \
    /velocity_smoother \
    /collision_monitor \
    /bt_navigator \
    /behavior_server \
    /waypoint_follower
do
    printf "%-28s " "$node"

    result=$(ros2 lifecycle get "$node" 2>/dev/null || true)

    if echo "$result" | grep -q "active \[3\]"; then
        echo "ACTIVE [3]"
    else
        echo
        echo "$result"
    fi
done

echo
echo "===== 8. CMD_VEL TYPE AUDIT ====="

for topic in \
    /cmd_vel_nav \
    /cmd_vel_smoothed \
    /diff_drive_controller/cmd_vel
do
    echo
    echo "--- $topic ---"
    ros2 topic type "$topic" 2>/dev/null || echo "topic not currently advertised"
done

echo
echo "===== 9. DUPLICATE NODE AUDIT ====="

echo "--- AMCL ---"
ros2 node list --no-daemon 2>/dev/null | grep -c '^/amcl$' || true

echo "--- map_server ---"
ros2 node list --no-daemon 2>/dev/null | grep -c '^/map_server$' || true

echo "--- planner_server ---"
ros2 node list --no-daemon 2>/dev/null | grep -c '^/planner_server$' || true

echo "--- controller_server ---"
ros2 node list --no-daemon 2>/dev/null | grep -c '^/controller_server$' || true

echo
echo "============================================================"
echo " RECOVERY AUDIT COMPLETE"
echo "============================================================"
echo
echo "GAZEBO:       preserved"
echo "LOCALIZATION: checked/repaired if necessary"
echo "NAV2:         checked/started if necessary"
echo "DUPLICATES:   checked"
echo "DDS SHM:      disabled for recovery-launched stacks"
echo "MOVEMENT:     NONE"
echo
echo "MANDATORY BEFORE MOVEMENT:"
echo "CHECK CURRENT POSE -> VERIFY TF -> CHOOSE GOAL -> MOVE"
echo
echo "Logs:"
echo "  $LOGDIR/localization.log"
echo "  $LOGDIR/navigation.log"
echo
