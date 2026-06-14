"""Wiederverwendbare Basis fuer Sensor-Mockups.

Ein neuer Sensor ist damit nur wenige Zeilen Code (siehe temp_sensor.py /
motion_sensor.py) -- das demonstriert Erweiterbarkeit. Jeder Sensor:
  1. meldet sich beim Start als "online" (retained),
  2. erzeugt periodisch einen Messwert (deterministisch, siehe common.simulator),
  3. publiziert ihn als Telemetrie-Envelope auf den Bus.
"""
from __future__ import annotations

import asyncio
import time

from common.mqtt import client_for, run_forever
from common.simulator import next_reading
from common.topics import availability_topic, envelope, telemetry_topic


def sim_hour() -> float:
    """Simulierte Tageszeit -- 1 reale Minute entspricht 1 simulierten Stunde."""
    return (time.time() / 60) % 24


async def _run(device_id, role, unit, metric, interval):
    history: list[float] = []
    async with client_for(device_id) as client:
        await client.publish(availability_topic(device_id), b"online", qos=1, retain=True)
        print(f"[{device_id}] online (Rolle: {role})")
        while True:
            value = next_reading(role, sim_hour(), history)
            history.append(value)
            await client.publish(
                telemetry_topic(device_id, metric),
                envelope(device_id=device_id, metric=metric, value=value, unit=unit),
                qos=1,
            )
            print(f"[{device_id}] {metric}={value}{unit}")
            await asyncio.sleep(interval)


def run_sensor(device_id, role, unit, metric, interval: float = 5.0) -> None:
    asyncio.run(run_forever(lambda: _run(device_id, role, unit, metric, interval), name=device_id))
