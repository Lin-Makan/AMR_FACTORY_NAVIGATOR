#!/bin/bash

source /opt/ros/jazzy/setup.bash

if [ -f "$HOME/ros2_ws/install/setup.bash" ]; then
    source "$HOME/ros2_ws/install/setup.bash"
fi

cd "$HOME/ros2_ws"

export AMR_PROJECT="AMR_FACTORY_NAVIGATOR"
export AMR_WS="$HOME/ros2_ws"

echo "=========================================="
echo " AMR_FACTORY_NAVIGATOR"
echo " ROS 2 Jazzy"
echo " Workspace: $AMR_WS"
echo "=========================================="
