from setuptools import setup, find_packages

setup(
    name="ota-backend",
    version="0.1.0",
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        "flask",
        "requests",
        "paho-mqtt",
    ],
    data_files=[
        ("/usr/lib/systemd/system", ["systemd/ota-backend.service"]),
        ("/etc/ota-backend", ["config/default-config.json"]),
    ],
)
