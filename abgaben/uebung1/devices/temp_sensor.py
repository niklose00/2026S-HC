"""Temperatursensor (simuliert)."""
from devices.sensor_base import run_sensor

if __name__ == "__main__":
    run_sensor(
        device_id="temp-living",
        role="temperature",
        unit="\u00b0C",
        metric="temperature",
        interval=5.0,
    )
