import math

import rclpy
from rclpy.node import Node

from sensor_msgs.msg import LaserScan
from std_msgs.msg import Bool, Float32


class ObstacleDetector(Node):

    def __init__(self):
        super().__init__('obstacle_detector')

        self.declare_parameter('obstacle_distance', 0.50)
        self.declare_parameter('forward_angle', 45.0)

        self.obstacle_distance = self.get_parameter(
            'obstacle_distance'
        ).value

        self.forward_angle = self.get_parameter(
            'forward_angle'
        ).value

        self.scan_sub = self.create_subscription(
            LaserScan,
            '/scan',
            self.scan_callback,
            10
        )

        self.obstacle_pub = self.create_publisher(
            Bool,
            '/obstacle_detected',
            10
        )

        self.distance_pub = self.create_publisher(
            Float32,
            '/nearest_obstacle_distance',
            10
        )

        self.get_logger().info(
            f'Obstacle detector started. '
            f'Safety distance: {self.obstacle_distance:.2f} m, '
            f'Forward sector: +/- {self.forward_angle:.1f} degrees'
        )

    def scan_callback(self, msg):

        forward_ranges = []

        for i, r in enumerate(msg.ranges):

            if not math.isfinite(r):
                continue

            angle = msg.angle_min + i * msg.angle_increment

            angle_degrees = math.degrees(angle)

            if abs(angle_degrees) <= self.forward_angle:
                forward_ranges.append(r)

        obstacle_detected = False
        nearest_distance = float('inf')

        if forward_ranges:
            nearest_distance = min(forward_ranges)

            if nearest_distance < self.obstacle_distance:
                obstacle_detected = True

        obstacle_msg = Bool()
        obstacle_msg.data = obstacle_detected
        self.obstacle_pub.publish(obstacle_msg)

        distance_msg = Float32()
        distance_msg.data = nearest_distance
        self.distance_pub.publish(distance_msg)

        if obstacle_detected:
            self.get_logger().warn(
                f'OBSTACLE DETECTED IN FRONT: '
                f'{nearest_distance:.2f} m'
            )
        else:
            self.get_logger().info(
                f'FORWARD PATH CLEAR: '
                f'{nearest_distance:.2f} m'
            )


def main(args=None):

    rclpy.init(args=args)

    node = ObstacleDetector()

    try:
        rclpy.spin(node)

    except KeyboardInterrupt:
        pass

    finally:
        node.destroy_node()

        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
