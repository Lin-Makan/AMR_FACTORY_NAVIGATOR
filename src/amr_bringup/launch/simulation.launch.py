import os

from launch import LaunchDescription
from launch.actions import ExecuteProcess, TimerAction
from launch.substitutions import Command, PathJoinSubstitution
from launch_ros.substitutions import FindPackageShare
from launch_ros.actions import Node


def generate_launch_description():

    package_share = FindPackageShare("amr_bringup")

    world = PathJoinSubstitution([
        package_share,
        "worlds",
        "empty_world.sdf"
    ])

    robot = PathJoinSubstitution([
        package_share,
        "robots",
        "robot.urdf"
    ])

    # Preserve the existing Gazebo system plugin path
    # and add the Gazebo GUI plugin path.
    gz_system_plugin_path = os.pathsep.join(filter(None, [
        "/opt/ros/jazzy/opt/gz_sim_vendor/lib/gz-sim-8/plugins",
        os.environ.get("GZ_SIM_SYSTEM_PLUGIN_PATH", ""),
        "/opt/ros/jazzy/lib",
    ]))

    gz_gui_plugin_path = (
        "/opt/ros/jazzy/opt/gz_sim_vendor/lib/gz-sim-8/plugins/gui"
    )

    # Start Gazebo Sim
    gazebo = ExecuteProcess(
        cmd=["gz", "sim", world, "-s", "-r"],
        output="screen",
        additional_env={
            "GZ_SIM_SYSTEM_PLUGIN_PATH": gz_system_plugin_path,
            "GZ_GUI_PLUGIN_PATH": gz_gui_plugin_path
        }
    )

    # Bridge Gazebo simulation clock and LiDAR to ROS 2
    bridge = Node(
        package="ros_gz_bridge",
        executable="parameter_bridge",
        arguments=[
            "/clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock",
            "/scan@sensor_msgs/msg/LaserScan[gz.msgs.LaserScan"
        ]
    )

    # Publish the robot description and TF
    robot_state_publisher = Node(
        package="robot_state_publisher",
        executable="robot_state_publisher",
        name="robot_state_publisher",
        output="screen",
        parameters=[
            {
                "robot_description": Command(["cat ", robot]),
                 "use_sim_time": True  
            }
        ]
    )

    # Spawn the AMR into Gazebo
    spawn_robot = TimerAction(
        period=5.0,
        actions=[
            ExecuteProcess(
                cmd=[
                    "ros2",
                    "run",
                    "ros_gz_sim",
                    "create",
                    "-name",
                    "amr_robot",
                    "-file",
                    robot,
                    "-x",
                    "0",
                    "-y",
                    "0",
                    "-z",
                    "0.15"
                ],
                output="screen"
            )
        ]
    )

    # Spawn joint state broadcaster
    joint_state_broadcaster = TimerAction(
        period=10.0,
        actions=[
            Node(
                package="controller_manager",
                executable="spawner",
                arguments=["joint_state_broadcaster"],
                output="screen"
            )
        ]
    )

    # Spawn differential drive controller
    diff_drive_controller = TimerAction(
        period=15.0,
        actions=[
            Node(
                package="controller_manager",
                executable="spawner",
                arguments=["diff_drive_controller"],
                output="screen"
            )
        ]
    )

    return LaunchDescription([
        gazebo,
        bridge,
        robot_state_publisher,
        spawn_robot,
        joint_state_broadcaster,
        diff_drive_controller
    ])
