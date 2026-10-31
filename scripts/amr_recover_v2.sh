#!/usr/bin/env bash
set -u

WS="$HOME/ros2_ws"
SCRIPTS="$WS/scripts"
LOGDIR="$WS/.amr_recovery_logs"

MAP="$WS/src/amr_bringup/maps/factory_map.yaml"
LOC_PARAMS="$WS/src/amr_bringup/config/nav2_localization_params.yaml"
NAV_LAUNCH="$WS/src/amr_navigation/launch/navigation.launch.py"
NAV_PARAMS="$WS/src/amr_navigation/config/nav2_params.yaml"

mkdir -p "$LOGDIR"

# ROS setup scripts expect some optional environment variables to be unset.
# Source them with nounset disabled, then restore the recovery script's strict mode.
set +u
source /opt/ros/jazzy/setup.bash
source "$WS/install/setup.bash"
set -u

export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export RMW_FASTRTPS_USE_SHM=0
export GZ_SIM_SYSTEM_PLUGIN_PATH=/opt/ros/jazzy/lib

echo
echo "============================================================"
echo " AMR_FACTORY_NAVIGATOR — PERSISTENT RECOVERY V2"
echo "============================================================"
echo
echo "NO MOVEMENT COMMANDS WILL BE SENT."
echo

# ------------------------------------------------------------
# 1. Required packages
# ------------------------------------------------------------

echo "===== 1. CHECK REQUIRED PACKAGE VERSIONS ====="

CONTROL_PKGS=(
  ros-jazzy-controller-manager
  ros-jazzy-diagnostic-updater
  ros-jazzy-diff-drive-controller
  ros-jazzy-gz-ros2-control
  ros-jazzy-joint-state-broadcaster
  ros-jazzy-ros2-control
  ros-jazzy-ros2-controllers
)

# Known-good controller stack previously verified for this project.
# These are MINIMUM versions.
# Newer installed versions are always preserved; this logic never downgrades.
declare -A MIN_CONTROL_VERSIONS=(
  [ros-jazzy-controller-manager]="4.48.1"
  [ros-jazzy-diagnostic-updater]="4.2.7"
  [ros-jazzy-diff-drive-controller]="4.42.1"
  [ros-jazzy-gz-ros2-control]="1.2.20"
  [ros-jazzy-joint-state-broadcaster]="4.42.1"
  [ros-jazzy-ros2-control]="4.48.1"
  [ros-jazzy-ros2-controllers]="4.42.1"
)

NEED_CONTROL_REPAIR=0
CONTROL_INSTALL_ARGS=()

# ------------------------------------------------------------
# APT metadata recovery
# ------------------------------------------------------------
# Construct resets have previously restored older ROS packages.
# A stale APT index can temporarily report the installed old
# package as the candidate even when packages.ros.org provides
# the known-good version.
#
# Refresh APT metadata at most once during this recovery run.
# This operation only refreshes package indexes. It does NOT
# install or upgrade packages.

APT_REFRESH_ATTEMPTED=0

refresh_apt_metadata() {
  if [ "$APT_REFRESH_ATTEMPTED" -eq 1 ]; then
    return 0
  fi

  APT_REFRESH_ATTEMPTED=1

  echo
  echo "===== APT METADATA REFRESH ====="
  echo "APT candidate is missing or below the known-good minimum."
  echo "Refreshing APT metadata before declaring recovery blocked."
  echo "NO packages will be installed by this refresh."

  if sudo apt-get update; then
    echo "PASS: APT metadata refresh completed."
    return 0
  fi

  echo "FAIL: APT metadata refresh failed."
  echo "Recovery will STOP before package changes."
  return 1
}


echo
echo "===== 1. CONTROLLER STACK VERSION GATE ====="
echo "Known-good minimum versions are enforced."
echo "Newer installed versions will NOT be downgraded."

for pkg in "${CONTROL_PKGS[@]}"; do
  installed="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)"
  candidate="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
  required="${MIN_CONTROL_VERSIONS[$pkg]}"

  echo
  echo "$pkg"
  echo "  installed: ${installed:-MISSING}"
  echo "  required minimum: $required"
  echo "  apt candidate: ${candidate:-UNKNOWN}"

  # Missing package.
  if [ -z "$installed" ]; then
    echo "  ACTION: package missing."

    if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
      echo "  FAIL: no usable APT candidate available."
      echo "  Recovery will STOP before package changes."
      exit 10
    fi

    if ! dpkg --compare-versions "$candidate" ge "$required"; then
      echo "  FAIL: APT candidate $candidate is below required $required."
      echo "  Recovery will STOP before package changes."
      exit 10
    fi

    echo "  ACTION: install $pkg at $candidate."
    CONTROL_INSTALL_ARGS+=("$pkg=$candidate")
    NEED_CONTROL_REPAIR=1
    continue
  fi

  # Installed version already meets the known-good minimum.
  if dpkg --compare-versions "$installed" ge "$required"; then
    echo "  PASS: installed version meets known-good minimum."
    continue
  fi

  # Installed version is too old.
  echo "  ACTION: installed version is below known-good minimum."

  if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
    echo "  FAIL: no APT candidate available for $pkg."
    echo "  Recovery will STOP before package changes."
    exit 10
  fi

  if ! dpkg --compare-versions "$candidate" ge "$required"; then
    echo "  APT candidate $candidate is below required $required."

    if [ "$APT_REFRESH_ATTEMPTED" -eq 0 ]; then
      echo "  Possible stale APT metadata after Construct reset."
      if ! refresh_apt_metadata; then
        exit 10
      fi

      candidate="$(apt-cache policy "$pkg" 2>/dev/null |         awk '/Candidate:/ {print $2; exit}')"

      echo "  refreshed apt candidate: ${candidate:-UNKNOWN}"
    fi

    if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
      echo "  FAIL: no usable APT candidate after metadata refresh."
      echo "  Recovery will STOP before package changes."
      exit 10
    fi

    if ! dpkg --compare-versions "$candidate" ge "$required"; then
      echo "  FAIL: refreshed APT candidate $candidate is below required $required."
      echo "  Repository still does not provide a known-good version."
      echo "  Recovery will STOP before package changes."
      exit 10
    fi
  fi

  echo "  ACTION: upgrade $pkg to $candidate."
  CONTROL_INSTALL_ARGS+=("$pkg=$candidate")
  NEED_CONTROL_REPAIR=1
done

if [ "$NEED_CONTROL_REPAIR" -eq 1 ]; then
  echo
  echo "Controller stack requires targeted repair."
  echo "Installing ONLY:"
  printf '  %s\n' "${CONTROL_INSTALL_ARGS[@]}"

  sudo apt-get install -y "${CONTROL_INSTALL_ARGS[@]}" || {
    echo
    echo "FAIL: targeted controller package repair failed."
    echo "STOPPING BEFORE GAZEBO/LOCALIZATION/NAV2."
    exit 11
  }
else
  echo
  echo "PASS: controller stack already meets known-good minimum versions."
fi

echo
echo "===== POST-REPAIR CONTROLLER VERSION CHECK ====="

for pkg in "${CONTROL_PKGS[@]}"; do
  installed="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)"
  required="${MIN_CONTROL_VERSIONS[$pkg]}"

  echo "$pkg: ${installed:-MISSING} (minimum $required)"

  if [ -z "$installed" ] || \
     ! dpkg --compare-versions "$installed" ge "$required"; then
    echo "FAIL: $pkg does not meet the required minimum."
    echo "STOPPING BEFORE GAZEBO/LOCALIZATION/NAV2."
    exit 12
  fi
done

echo "PASS: all controller packages meet known-good minimum versions."

echo "===== 2. VERIFY NAV2 AND SLAM PACKAGES ====="

NAV2_PKGS=(
  ros-jazzy-navigation2
  ros-jazzy-nav2-bringup
  ros-jazzy-nav2-amcl
  ros-jazzy-nav2-map-server
  ros-jazzy-nav2-lifecycle-manager
  ros-jazzy-nav2-planner
  ros-jazzy-nav2-controller
  ros-jazzy-nav2-bt-navigator
  ros-jazzy-nav2-behaviors
  ros-jazzy-nav2-velocity-smoother
  ros-jazzy-nav2-collision-monitor
  ros-jazzy-nav2-waypoint-follower
  ros-jazzy-slam-toolbox
  ros-jazzy-tf2-tools
)

NAV2_MISSING=()
for pkg in "${NAV2_PKGS[@]}"; do
  status="$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)"
  if [ "$status" = "install ok installed" ]; then
    echo "OK: $pkg"
  else
    echo "MISSING: $pkg"
    NAV2_MISSING+=("$pkg")
  fi
done

if [ "${#NAV2_MISSING[@]}" -gt 0 ]; then
  echo "Missing Nav2/SLAM packages detected; checking APT candidates."
  for pkg in "${NAV2_MISSING[@]}"; do
    candidate="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
      echo "No APT candidate for $pkg; refreshing metadata once."
      if [ "$APT_REFRESH_ATTEMPTED" -eq 0 ]; then
        refresh_apt_metadata || exit 13
      fi
      candidate="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    fi
    if [ -z "$candidate" ] || [ "$candidate" = "(none)" ]; then
      echo "FAIL: no candidate available for $pkg."
      echo "STOPPING before Gazebo/localization/Nav2."
      exit 13
    fi
  done

  echo "Installing only missing Nav2/SLAM packages:"
  printf '  %s\n' "${NAV2_MISSING[@]}"
  sudo apt-get install -y "${NAV2_MISSING[@]}" || {
    echo "FAIL: missing Nav2/SLAM package installation failed."
    exit 13
  }

  for pkg in "${NAV2_MISSING[@]}"; do
    status="$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)"
    if [ "$status" != "install ok installed" ]; then
      echo "FAIL: post-install verification failed for $pkg."
      exit 13
    fi
    echo "PASS: installed and verified $pkg"
  done
fi

# ------------------------------------------------------------
# 3. Gazebo
# ------------------------------------------------------------

echo
echo "===== 3. GAZEBO ====="

if pgrep -af 'gz sim' >/dev/null 2>&1; then
  echo "Gazebo process already exists."
  echo "KEEPING CURRENT GAZEBO."
else
  echo "Starting Gazebo..."

  nohup bash -c "
    source /opt/ros/jazzy/setup.bash
    source '$WS/install/setup.bash'
    export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
    export RMW_FASTRTPS_USE_SHM=0
    export GZ_SIM_SYSTEM_PLUGIN_PATH=/opt/ros/jazzy/lib
    ros2 launch amr_bringup simulation.launch.py
  " > "$LOGDIR/gazebo.log" 2>&1 &

  echo $! > "$LOGDIR/gazebo.pid"
fi

echo "Waiting for controller_manager service readiness..."
echo "This may take up to 60 seconds during Gazebo startup."

CONTROLLER_MANAGER_READY=0

for i in $(seq 1 60); do
  if timeout 4 ros2 service list --no-daemon 2>/dev/null |        grep -qx "/controller_manager/list_controllers"; then
    CONTROLLER_MANAGER_READY=1
    echo "PASS: controller_manager service is ready after ${i}s."
    break
  fi

  if [ "$i" -eq 1 ] || [ $((i % 10)) -eq 0 ]; then
    echo "  Still waiting... ${i}/60s"
  fi

  sleep 1
done

if [ "$CONTROLLER_MANAGER_READY" -ne 1 ]; then
  echo "FAIL: controller_manager service did not become ready within 60 seconds."
  echo "This is a real readiness failure, not merely a node-discovery delay."
  echo
  echo "Relevant nodes:"
  timeout 5 ros2 node list --no-daemon 2>/dev/null |     grep -E "controller_manager|gz_ros_control|ros_gz_bridge" || true
  echo
  echo "Relevant services:"
  timeout 5 ros2 service list --no-daemon 2>/dev/null |     grep "controller_manager" || true
  echo
  echo "See: $LOGDIR/gazebo.log"
  exit 20
fi

echo "Verifying controller_manager can answer list_controllers..."

if timeout 8 ros2 control list_controllers >/dev/null 2>&1; then
  echo "PASS: controller_manager is responding."
else
  echo "FAIL: controller_manager service exists but is not responding."
  echo "See: $LOGDIR/gazebo.log"
  exit 21
fi

# ------------------------------------------------------------
# 4. Controllers
# ------------------------------------------------------------

echo
echo "===== 4. CONTROLLERS ====="

echo "Checking required controllers..."

CONTROLLER_STATE="$(timeout 8 ros2 control list_controllers 2>/dev/null || true)"
printf '%s\n' "$CONTROLLER_STATE"

CONTROLLERS_OK=1

if printf '%s\n' "$CONTROLLER_STATE" | grep -q \
  '^joint_state_broadcaster .* active'; then
  echo "PASS: joint_state_broadcaster active."
else
  echo "MISSING/INACTIVE: joint_state_broadcaster."
  CONTROLLERS_OK=0
fi

if printf '%s\n' "$CONTROLLER_STATE" | grep -q \
  '^diff_drive_controller .* active'; then
  echo "PASS: diff_drive_controller active."
else
  echo "MISSING/INACTIVE: diff_drive_controller."
  CONTROLLERS_OK=0
fi

if [ "$CONTROLLERS_OK" -ne 1 ]; then
  echo "Attempting controller activation..."

  if ! timeout 15 ros2 control switch_controllers \
      --activate joint_state_broadcaster 2>&1; then
    echo "WARNING: joint_state_broadcaster activation request failed."
  fi

  if ! timeout 15 ros2 control switch_controllers \
      --activate diff_drive_controller 2>&1; then
    echo "WARNING: diff_drive_controller activation request failed."
  fi

  sleep 3
fi

echo
echo "Final controller verification..."

CONTROLLER_STATE="$(timeout 8 ros2 control list_controllers 2>/dev/null || true)"
printf '%s\n' "$CONTROLLER_STATE"

if ! printf '%s\n' "$CONTROLLER_STATE" | grep -q \
  '^joint_state_broadcaster .* active'; then
  echo "FAIL: joint_state_broadcaster is not active."
  echo "STOPPING BEFORE LOCALIZATION/NAV2."
  exit 21
fi

if ! printf '%s\n' "$CONTROLLER_STATE" | grep -q \
  '^diff_drive_controller .* active'; then
  echo "FAIL: diff_drive_controller is not active."
  echo "STOPPING BEFORE LOCALIZATION/NAV2."
  exit 21
fi

echo "PASS: all required controllers are ACTIVE."

# ------------------------------------------------------------
# 5. Localization
# ------------------------------------------------------------

echo
echo "===== 5. LOCALIZATION ====="

if timeout 5 ros2 node list --no-daemon 2>/dev/null | grep -qx "/amcl"; then
  echo "AMCL already running."
  echo "KEEPING CURRENT LOCALIZATION."
else
  echo "Starting localization..."

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

  echo $! > "$LOGDIR/localization.pid"
fi

echo "Waiting for localization..."

for i in $(seq 1 60); do
  nodes="$(timeout 4 ros2 node list --no-daemon 2>/dev/null || true)"

  if echo "$nodes" | grep -qx "/amcl" && \
     echo "$nodes" | grep -qx "/map_server" && \
     echo "$nodes" | grep -qx "/lifecycle_manager_localization"; then
    echo "PASS: localization nodes detected."
    break
  fi

  sleep 1
done

if ! timeout 5 ros2 node list --no-daemon 2>/dev/null | grep -qx "/amcl"; then
  echo "FAIL: AMCL not detected."
  echo "See: $LOGDIR/localization.log"
  exit 22
fi

# ------------------------------------------------------------
# 6. LOCALIZATION LIFECYCLE SAFETY GATE
# ------------------------------------------------------------

echo
echo "===== 6. LOCALIZATION LIFECYCLE SAFETY GATE ====="
echo
echo "Checking AMCL and map_server lifecycle state."
echo "No pose will be published."

LOCALIZATION_LIFECYCLE_OK=1

for node in "/map_server" "/amcl"; do
  echo
  echo "--- $node ---"

  if ! timeout 5 ros2 node list --no-daemon 2>/dev/null |       grep -qx "$node"; then
    echo "FAIL: $node is not present."
    LOCALIZATION_LIFECYCLE_OK=0
    continue
  fi

  STATE="$(timeout 5 ros2 lifecycle get "$node" 2>/dev/null || true)"
  printf '%s\n' "$STATE"

  if printf '%s\n' "$STATE" | grep -Eq '^[[:space:]]*active([[:space:]]|$)'; then
    echo "PASS: $node is ACTIVE."
  else
    echo "FAIL: $node is NOT ACTIVE."
    LOCALIZATION_LIFECYCLE_OK=0
  fi
done

if [ "$LOCALIZATION_LIFECYCLE_OK" -ne 1 ]; then
  echo
  echo "STOP: localization lifecycle is not fully ACTIVE."
  echo "Nav2 will NOT be started."
  echo "NO movement command has been sent."
  exit 22
fi

echo
echo "PASS: AMCL and map_server are ACTIVE."

# ------------------------------------------------------------
# 6. AMCL pose — READ ONLY
# ------------------------------------------------------------

echo
echo "===== 6. AMCL POSE ====="

echo "AMCL initial pose is configured persistently in:"
echo "$LOC_PARAMS"
echo
echo "Reading /amcl_pose without publishing a new pose..."

if timeout 10 ros2 topic echo /amcl_pose --once 2>/dev/null; then
  echo "PASS: /amcl_pose received."
else
  echo "FAIL: /amcl_pose was not received."
  echo "STOPPING BEFORE NAV2."
  echo "See: $LOGDIR/localization.log"
  exit 22
fi

# ------------------------------------------------------------
# 7. ODOM
# ------------------------------------------------------------

echo
echo "===== 7. ODOM ====="

timeout 8 ros2 topic echo /diff_drive_controller/odom --once 2>/dev/null || {
  echo "FAIL: odometry not received."
  exit 23
}

# ------------------------------------------------------------
# 8. TF SAFETY GATE
# ------------------------------------------------------------

echo
echo "===== 8. TF SAFETY GATE ====="

echo "--- odom -> base_link ---"
ODOM_BASE="$(timeout 5 ros2 run tf2_ros tf2_echo odom base_link 2>&1 || true)"
printf '%s\n' "$ODOM_BASE" | head -30

if printf '%s\n' "$ODOM_BASE" | grep -q "At time"; then
  echo
  echo "PASS: odom -> base_link exists."
else
  echo
  echo "STOP: odom -> base_link is NOT available."
  echo
  echo "Nav2 will NOT be started."
  echo "NO movement command has been sent."
  echo
  echo "This is the current odometry/TF problem to diagnose."
  echo "See: $LOGDIR/gazebo.log"
  exit 24
fi

echo
echo "--- map -> odom ---"
MAP_ODOM="$(timeout 5 ros2 run tf2_ros tf2_echo map odom 2>&1 || true)"
printf '%s\n' "$MAP_ODOM" | head -30

if printf '%s\n' "$MAP_ODOM" | grep -q "At time"; then
  echo
  echo "PASS: map -> odom exists."
else
  echo
  echo "STOP: map -> odom is NOT available."
  echo
  echo "Nav2 will NOT be started."
  echo "NO movement command has been sent."
  echo
  echo "This is the current localization/TF problem to diagnose."
  echo "See: $LOGDIR/localization.log"
  exit 24
fi

echo
echo "--- map -> base_link ---"
MAP_BASE="$(timeout 5 ros2 run tf2_ros tf2_echo map base_link 2>&1 || true)"
printf '%s\n' "$MAP_BASE" | head -30

if printf '%s\n' "$MAP_BASE" | grep -q "At time"; then
  echo
  echo "PASS: map -> base_link exists."
else
  echo
  echo "STOP: map -> base_link is NOT available."
  echo
  echo "Nav2 will NOT be started."
  echo "NO movement command has been sent."
  exit 24
fi

# ------------------------------------------------------------
# 9. CUSTOM NAV2
# ------------------------------------------------------------

echo
echo "===== 9. CUSTOM NAV2 ====="

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
  if timeout 4 ros2 node list --no-daemon 2>/dev/null | grep -qx "$node"; then
    echo "FOUND: $node"
  else
    echo "MISSING: $node"
    NAV2_OK=0
  fi
done

if [ "$NAV2_OK" -eq 1 ]; then
  echo "PASS: custom Nav2 already running."
else
  echo "Starting custom Nav2..."

  (
    source /opt/ros/jazzy/setup.bash
    source "$WS/install/setup.bash"
    export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
    export RMW_FASTRTPS_USE_SHM=0

    ros2 launch "$NAV_LAUNCH" \
      params_file:="$NAV_PARAMS"
  ) > "$LOGDIR/navigation.log" 2>&1 &

  echo $! > "$LOGDIR/navigation.pid"

  echo "Waiting for required Nav2 nodes (up to 60 seconds)..."

  NAV2_PRESENT=0

  for i in $(seq 1 60); do
    NAV2_PRESENT=1

    for node in "${NAV2_NODES[@]}"; do
      if ! timeout 4 ros2 node list --no-daemon 2>/dev/null |           grep -qx "$node"; then
        NAV2_PRESENT=0
        break
      fi
    done

    if [ "$NAV2_PRESENT" -eq 1 ]; then
      echo "PASS: all required Nav2 nodes detected after ${i}s."
      break
    fi

    if [ "$i" -eq 1 ] || [ $((i % 10)) -eq 0 ]; then
      echo "  Still waiting for Nav2... ${i}/60s"
    fi

    sleep 1
  done

  for node in "${NAV2_NODES[@]}"; do
    if timeout 4 ros2 node list --no-daemon 2>/dev/null | grep -qx "$node"; then
      echo "FOUND: $node"
    else
      echo "MISSING: $node"
    fi
  done
fi

# ------------------------------------------------------------
# 10. NAV2 LIFECYCLE SAFETY GATE
# ------------------------------------------------------------

echo
echo "===== 10. NAV2 LIFECYCLE SAFETY GATE ====="
echo
echo "Checking that every required Nav2 lifecycle node is ACTIVE."
echo "No navigation goal will be sent."

NAV2_LIFECYCLE_NODES=(
  "/planner_server"
  "/controller_server"
  "/velocity_smoother"
  "/collision_monitor"
  "/bt_navigator"
  "/behavior_server"
  "/waypoint_follower"
)

NAV2_LIFECYCLE_OK=1

for node in "${NAV2_LIFECYCLE_NODES[@]}"; do
  echo
  echo "--- $node ---"

  if ! timeout 5 ros2 node list --no-daemon 2>/dev/null | grep -qx "$node"; then
    echo "FAIL: $node is not present."
    NAV2_LIFECYCLE_OK=0
    continue
  fi

  STATE="$(timeout 5 ros2 lifecycle get "$node" 2>/dev/null || true)"
  printf '%s\n' "$STATE"

  if printf '%s\n' "$STATE" | grep -Eq '^[[:space:]]*active([[:space:]]|$)'; then
    echo "PASS: $node is ACTIVE."
  else
    echo "FAIL: $node is NOT ACTIVE."
    NAV2_LIFECYCLE_OK=0
  fi
done

echo

if [ "$NAV2_LIFECYCLE_OK" -ne 1 ]; then
  echo "STOP: One or more required Nav2 lifecycle nodes are not ACTIVE."
  echo "Nav2 recovery is NOT considered successful."
  echo "NO movement command has been sent."
  echo "NO navigation goal has been sent."
  exit 25
fi

echo "PASS: All required Nav2 lifecycle nodes are ACTIVE."
echo "Nav2 is ready for a separate safety-gated navigation test."

echo
echo "============================================================"
echo " RECOVERY COMPLETE — SAFETY STOP"
echo "============================================================"
echo
echo "NO MOVEMENT COMMAND WAS SENT."
echo "NO NAVIGATION GOAL WAS SENT."
echo
echo "Required sequence remains:"
echo "CHECK CURRENT POSE"
echo "      -> VERIFY TF"
echo "      -> CHOOSE GOAL"
echo "      -> MOVE"
echo
echo "Logs:"
echo "  $LOGDIR/gazebo.log"
echo "  $LOGDIR/localization.log"
echo "  $LOGDIR/navigation.log"
echo
