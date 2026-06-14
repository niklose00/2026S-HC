"""Bewegungssensor (simuliert): publiziert 0/1-Ereignisse."""
from devices.sensor_base import run_sensor

if __name__ == "__main__":
    run_sensor(
        device_id="motion-hall",
        role="motion",
        unit="",
        metric="motion",
        interval=4.0,
    )
