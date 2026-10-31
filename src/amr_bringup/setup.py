from glob import glob
from setuptools import find_packages, setup

package_name = 'amr_bringup'

setup(
    name=package_name,
    version='0.0.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        (
            'share/ament_index/resource_index/packages',
            ['resource/' + package_name]
        ),
        (
            'share/' + package_name,
            ['package.xml']
        ),
        (
            'share/' + package_name + '/launch',
            ['launch/simulation.launch.py']
        ),
        (
            'share/' + package_name + '/worlds',
            ['worlds/empty_world.sdf']
        ),
        (
            'share/' + package_name + '/robots',
            ['robots/robot.urdf']
        ),
        (
            'share/' + package_name + '/config',
            glob('config/*')
        ),
        (
            'share/' + package_name + '/maps',
            glob('maps/*')
        ),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='user',
    maintainer_email='user@todo.todo',
    description='AMR Factory Navigator bringup package',
    license='Apache-2.0',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
        'console_scripts': [
        ],
    },
)
