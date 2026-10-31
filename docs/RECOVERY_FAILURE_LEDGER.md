# AMR Factory Navigator — Recovery Failure Ledger

## 2026-10-09 — Recovery script audit

### Confirmed package state
- `ros-jazzy-controller-manager`: installed 4.44.0; required minimum 4.48.1.
- `ros-jazzy-ros2-control`: installed 4.44.0; required minimum 4.48.1.
- `ros-jazzy-ros2-controllers`: installed 4.39.0; required minimum 4.42.1.
- `ros-jazzy-diff-drive-controller`: installed 4.39.0; required minimum 4.42.1.
- `ros-jazzy-joint-state-broadcaster`: installed 4.39.0; required minimum 4.42.1.
- `ros-jazzy-gz-ros2-control`: installed 1.2.17; required minimum 1.2.20.
- `ros-jazzy-diagnostic-updater`: installed 4.2.6; required minimum 4.2.7.
- APT metadata refresh completed on this date. No package installation was performed during this audit.

### Confirmed script defects
- Malformed Gazebo launch command.
- Malformed `ros2 service list` command.
- Missing whitespace in `timeout 8` and `ros2 node list --no-daemon`.
- Malformed `ros2 run tf2_ros tf2_echo` odometry check.
- Lifecycle checks used substring matching, which could accept `inactive` as `active`.
- Nav2 package installation lacked proper candidate and post-install verification.

### Safety status
- Recovery audit only; no movement command or navigation goal sent.
- Root cause of package-version reversion is not established.
- Full runtime recovery and topic/QoS audit remain pending.
