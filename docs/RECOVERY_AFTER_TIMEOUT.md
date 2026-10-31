# AMR_FACTORY_NAVIGATOR — Recovery After The Construct Timeout

## Golden rule

Do not reinstall everything after a session timeout.

The project has two kinds of state:

### Persistent

Stored in `~/ros2_ws`:

- source code
- URDF
- SDF
- maps
- Nav2 configuration
- SLAM configuration
- ros2_control configuration
- scripts
- manifests
- documentation

### Runtime

Must be recreated after a timeout:

- Gazebo
- ros2_control processes
- controllers
- AMCL
- Nav2
- lifecycle state
- ROS graph
- TF runtime
- MCAP recorder

## Recovery

Run:

```bash
cd ~/ros2_ws
./scripts/amr_recover.sh

