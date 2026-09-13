import rclpy
from rclpy.node import Node

from std_msgs.msg import Bool, Float32
from geometry_msgs.msg import TwistStamped


class MotionController(Node):

    def __init__(self):
        super().__init__('motion_controller')

        # --------------------------------------------------
        # Parameters
        # --------------------------------------------------

        self.declare_parameter('safe_distance', 0.50)
        self.declare_parameter('forward_speed', 0.10)
        self.declare_parameter('max_drive_time', 15.0)

        self.safe_distance = self.get_parameter(
            'safe_distance'
        ).value

        self.forward_speed = self.get_parameter(
            'forward_speed'
        ).value

        self.max_drive_time = self.get_parameter(
            'max_drive_time'
        ).value

        # --------------------------------------------------
        # State
        # --------------------------------------------------

        self.obstacle_detected = False
        self.nearest_distance = float('inf')

        # Safety stop becomes permanently active after
        # an obstacle is detected.
        self.safety_stop_latched = False

        # Prevents the robot from driving forever during
        # this controlled motion test.
        self.drive_started = False
        self.drive_start_time = None
        self.drive_time_expired = False

        self.last_state = None

        # --------------------------------------------------
        # Subscribers
        # --------------------------------------------------

        self.obstacle_sub = self.create_subscription(
            Bool,
            '/obstacle_detected',
            self.obstacle_callback,
            10
        )

        self.distance_sub = self.create_subscription(
            Float32,
            '/nearest_obstacle_distance',
            self.distance_callback,
            10
        )

        # --------------------------------------------------
        # Publisher
        # --------------------------------------------------

        self.cmd_pub = self.create_publisher(
            TwistStamped,
            '/diff_drive_controller/cmd_vel',
            10
        )

        # --------------------------------------------------
        # Control loop
        # --------------------------------------------------

        self.timer = self.create_timer(
            0.1,
            self.control_loop
        )

        self.get_logger().info(
            'Motion controller started.'
        )

        self.get_logger().info(
            f'Safe distance: {self.safe_distance:.2f} m'
        )

        self.get_logger().info(
            f'Forward speed: {self.forward_speed:.2f} m/s'
        )

        self.get_logger().info(
            f'Max drive time: {self.max_drive_time:.1f} s'
        )

    # ------------------------------------------------------
    # Obstacle callback
    # ------------------------------------------------------

    def obstacle_callback(self, msg):

        self.obstacle_detected = msg.data

    # ------------------------------------------------------
    # Distance callback
    # ------------------------------------------------------

    def distance_callback(self, msg):

        self.nearest_distance = msg.data

    # ------------------------------------------------------
    # Publish zero velocity
    # ------------------------------------------------------

    def publish_stop(self):

        cmd = TwistStamped()

        cmd.header.stamp = self.get_clock().now().to_msg()

        cmd.twist.linear.x = 0.0
        cmd.twist.linear.y = 0.0
        cmd.twist.linear.z = 0.0

        cmd.twist.angular.x = 0.0
        cmd.twist.angular.y = 0.0
        cmd.twist.angular.z = 0.0

        self.cmd_pub.publish(cmd)

    # ------------------------------------------------------
    # Control loop
    # ------------------------------------------------------

    def control_loop(self):

        # ==================================================
        # STATE 1:
        # SAFETY STOP LATCHED
        # ==================================================

        if self.safety_stop_latched:

            self.publish_stop()

            if self.last_state != 'LATCHED_STOP':

                self.get_logger().warn(
                    'SAFETY STOP LATCHED — '
                    'robot will remain stopped.'
                )

                self.last_state = 'LATCHED_STOP'

            return

        # ==================================================
        # STATE 2:
        # DRIVE TIME EXPIRED
        # ==================================================

        if self.drive_time_expired:

            self.publish_stop()

            if self.last_state != 'TIME_STOP':

                self.get_logger().info(
                    'MAX DRIVE TIME REACHED — '
                    'robot stopped.'
                )

                self.last_state = 'TIME_STOP'

            return

        # ==================================================
        # STATE 3:
        # OBSTACLE DETECTED
        # ==================================================

        if self.obstacle_detected:

            self.safety_stop_latched = True

            self.publish_stop()

            self.get_logger().warn(
                f'OBSTACLE DETECTED — '
                f'SAFETY STOP at '
                f'{self.nearest_distance:.2f} m'
            )

            self.last_state = 'STOP'

            return

        # ==================================================
        # STATE 4:
        # START MOTION TIMER
        # ==================================================

        if not self.drive_started:

            self.drive_started = True

            self.drive_start_time = self.get_clock().now()

            self.get_logger().info(
                'PATH CLEAR — starting controlled drive.'
            )

        # ==================================================
        # STATE 5:
        # CHECK DRIVE TIME
        # ==================================================

        current_time = self.get_clock().now()

        elapsed_time = (
            current_time - self.drive_start_time
        ).nanoseconds / 1e9

        if elapsed_time >= self.max_drive_time:

            self.drive_time_expired = True

            self.publish_stop()

            self.get_logger().info(
                f'Drive test completed after '
                f'{elapsed_time:.1f} s — STOP.'
            )

            self.last_state = 'TIME_STOP'

            return

        # ==================================================
        # STATE 6:
        # PATH CLEAR — MOVE
        # ==================================================

        cmd = TwistStamped()

        cmd.header.stamp = self.get_clock().now().to_msg()

        cmd.twist.linear.x = self.forward_speed
        cmd.twist.linear.y = 0.0
        cmd.twist.linear.z = 0.0

        cmd.twist.angular.x = 0.0
        cmd.twist.angular.y = 0.0
        cmd.twist.angular.z = 0.0

        self.cmd_pub.publish(cmd)

        if self.last_state != 'GO':

            self.get_logger().info(
                f'GO — moving at '
                f'{self.forward_speed:.2f} m/s'
            )

            self.last_state = 'GO'

    # ------------------------------------------------------
    # Shutdown safety
    # ------------------------------------------------------

    def destroy_node(self):

        self.get_logger().info(
            'Motion controller shutting down — STOPPING ROBOT.'
        )

        self.publish_stop()

        super().destroy_node()


# ----------------------------------------------------------
# Main
# ----------------------------------------------------------

def main(args=None):

    rclpy.init(args=args)

    node = MotionController()

    try:

        rclpy.spin(node)

    except KeyboardInterrupt:

        pass

    finally:

        if rclpy.ok():

            node.destroy_node()

            rclpy.shutdown()


if __name__ == '__main__':

    main()
