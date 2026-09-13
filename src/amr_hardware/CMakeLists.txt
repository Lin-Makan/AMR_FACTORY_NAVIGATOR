cmake_minimum_required(VERSION 3.8)

project(amr_hardware)

if(NOT CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 17)
endif()

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)

find_package(rclcpp REQUIRED)
find_package(rclcpp_lifecycle REQUIRED)

find_package(hardware_interface REQUIRED)
find_package(controller_manager REQUIRED)
find_package(pluginlib REQUIRED)

find_package(std_msgs REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(geometry_msgs REQUIRED)

include_directories(
  include
)

# Hardware interface library will be added in the next step.
# add_library(amr_hardware_interface SHARED
#   src/amr_hardware_interface.cpp
# )

# ament_target_dependencies(amr_hardware_interface
#   rclcpp
#   rclcpp_lifecycle
#   hardware_interface
#   pluginlib
# )

# pluginlib_export_plugin_description_file(
#   hardware_interface
#   amr_hardware_plugins.xml
# )

install(
  DIRECTORY include/
  DESTINATION include
)

ament_package()
