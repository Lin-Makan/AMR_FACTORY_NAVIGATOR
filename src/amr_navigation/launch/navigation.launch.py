from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    params_file = LaunchConfiguration("params_file")

    return LaunchDescription([
        DeclareLaunchArgument(
            "params_file",
            default_value="/home/user/ros2_ws/src/amr_navigation/config/nav2_params.yaml",
        ),

        Node(
            package="nav2_planner",
            executable="planner_server",
            name="planner_server",
            output="screen",
            parameters=[params_file],
        ),

        Node(
            package="nav2_controller",
            executable="controller_server",
            name="controller_server",
            output="screen",
            parameters=[params_file],
            remappings=[
                ("cmd_vel", "/cmd_vel_nav"),
                ("odom", "/diff_drive_controller/odom"),
            ],
        ),

        Node(
            package="nav2_velocity_smoother",
            executable="velocity_smoother",
            name="velocity_smoother",
            output="screen",
            parameters=[params_file],
            remappings=[
                ("cmd_vel", "/cmd_vel_nav"),
                ("cmd_vel_smoothed", "/cmd_vel_smoothed"),
            ],
        ),

        Node(
            package="nav2_collision_monitor",
            executable="collision_monitor",
            name="collision_monitor",
            output="screen",
            parameters=[params_file],
            remappings=[
                ("cmd_vel_smoothed", "/cmd_vel_smoothed"),
                ("cmd_vel", "/diff_drive_controller/cmd_vel"),
            ],
        ),

        Node(
            package="nav2_bt_navigator",
            executable="bt_navigator",
            name="bt_navigator",
            output="screen",
            parameters=[params_file],
        ),

        Node(
            package="nav2_behaviors",
            executable="behavior_server",
            name="behavior_server",
            output="screen",
            parameters=[params_file],
        ),

        Node(
            package="nav2_waypoint_follower",
            executable="waypoint_follower",
            name="waypoint_follower",
            output="screen",
            parameters=[params_file],
        ),

        Node(
            package="nav2_lifecycle_manager",
            executable="lifecycle_manager",
            name="lifecycle_manager_navigation",
            output="screen",
            parameters=[
                params_file,
                {
                    "autostart": True,
                    "node_names": [
                        "planner_server",
                        "controller_server",
                        "velocity_smoother",
                        "collision_monitor",
                        "bt_navigator",
                        "behavior_server",
                        "waypoint_follower",
                    ],
                },
            ],
        ),
    ])
