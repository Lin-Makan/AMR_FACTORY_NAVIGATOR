import math
import time
import random

import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from geometry_msgs.msg import TwistStamped
from sensor_msgs.msg import LaserScan


class AMRActionDemo(Node):
    def __init__(self):
        super().__init__('amr_action_demo')

        self.pub = self.create_publisher(
            TwistStamped,
            '/diff_drive_controller/cmd_vel',
            10
        )

        self.sub = self.create_subscription(
            LaserScan, '/scan', self.scan_callback,
            qos_profile_sensor_data
        )

        self.scan = None
        self.scan_time = 0.0

    def scan_callback(self, msg):
        self.scan = msg
        self.scan_time = time.monotonic()

    def publish(self, linear, angular):
        msg = TwistStamped()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = 'base_link'

        # Reverse linear mapping: logical forward = negative Gazebo command.
        msg.twist.linear.x = -linear
        msg.twist.angular.z = angular

        self.pub.publish(msg)

    def sector_min(self, centre, half_width):
        if self.scan is None:
            return None

        values = []
        s = self.scan

        for i, distance in enumerate(s.ranges):
            angle = s.angle_min + i * s.angle_increment
            difference = math.atan2(
                math.sin(angle - centre),
                math.cos(angle - centre)
            )

            if abs(difference) <= half_width:
                if math.isfinite(distance) and s.range_min <= distance <= s.range_max:
                    values.append(distance)

        return min(values) if values else None

    def safe(self, linear, angular):
        if self.scan is None or time.monotonic() - self.scan_time > 2.0:
            return False

        if linear > 0:
            distance = self.sector_min(0.0, 0.45)
            return distance is not None and distance > 0.65

        if linear < 0:
            distance = self.sector_min(math.pi, 0.45)
            return distance is not None and distance > 0.65

        if angular != 0:
            distance = self.sector_min(0.0, math.pi)
            return distance is not None and distance > 0.40

        return True

    def run_segment(self, name, linear, angular, duration):
        print(f'\n{name}: {duration:.1f} seconds', flush=True)
        start = time.monotonic()

        while rclpy.ok() and time.monotonic() - start < duration:
            rclpy.spin_once(self, timeout_sec=0.02)

            if not self.safe(linear, angular):
                self.publish(0.0, 0.0)
                print('SAFETY STOP: obstacle or missing/stale LiDAR.', flush=True)
                return

            self.publish(linear, angular)
            time.sleep(0.05)

        self.publish(0.0, 0.0)
        time.sleep(0.3)


def main():
    rclpy.init()
    node = AMRActionDemo()

    try:
        print('Waiting for LiDAR...', flush=True)
        deadline = time.monotonic() + 8.0

        while rclpy.ok() and node.scan is None and time.monotonic() < deadline:
            rclpy.spin_once(node, timeout_sec=0.1)

        if node.scan is None:
            print('No LiDAR received. No movement will be commanded.')
            return

        print('LiDAR ready. Starting action demonstration.', flush=True)

        # Forward, then reverse along approximately the same path.
        node.run_segment('LOGICAL FORWARD', 0.15, 0.0, 4.0)
        node.run_segment('LOGICAL REVERSE / RETURN', -0.15, 0.0, 4.0)

        # Rotation demonstration.
        node.run_segment('ROTATE LEFT', 0.0, 0.55, 3.0)
        node.run_segment('ROTATE RIGHT', 0.0, -0.55, 3.0)
        node.run_segment('FULL LEFT ROTATION', 0.0, 0.55, 11.4)

        # Bounded random movement trials.
        random.seed()
        for i in range(6):
            direction = random.choice([1, -1])
            turn = random.choice([-0.45, 0.45, 0.0])
            duration = random.uniform(1.5, 3.0)

            node.run_segment(
                f'RANDOM TRIAL {i + 1}',
                direction * 0.12,
                turn,
                duration
            )

        print('\nDEMONSTRATION COMPLETE.', flush=True)

    except KeyboardInterrupt:
        print('\nInterrupted by user.', flush=True)

    finally:
        for _ in range(10):
            node.publish(0.0, 0.0)
            rclpy.spin_once(node, timeout_sec=0.02)

        print('STOP command sent.', flush=True)
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
