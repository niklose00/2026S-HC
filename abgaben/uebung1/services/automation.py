"""Automations-/Regel-Engine (laeuft am Edge).

Beispielregel: Wird Bewegung erkannt, schaltet das Licht ein; bleibt es eine
Weile ruhig, schaltet es wieder aus. Die Engine spricht nur Topics an und kennt
weder die konkrete Lampe noch den Sensor direkt -> lose Kopplung. Neue Regeln
oder Geraete lassen sich ergaenzen, ohne bestehende Komponenten zu aendern.
"""
from __future__ import annotations

import asyncio
import time

from common.mqtt import client_for, run_forever
from common.topics import (
    ALL_TELEMETRY,
    availability_topic,
    command_topic,
    envelope,
    parse,
)

SERVICE = "automation"
LIGHT = "light-living"
TIMEOUT = 15  # Sekunden ohne Bewegung -> Licht aus


async def _run():
    last_motion = 0.0
    light_on = False

    async with client_for(SERVICE) as client:
        await client.publish(availability_topic(SERVICE), b"online", qos=1, retain=True)
        await client.subscribe(ALL_TELEMETRY)
        print("[automation] Regel-Engine aktiv")

        async def auto_off():
            nonlocal light_on
            while True:
                await asyncio.sleep(2)
                if light_on and time.time() - last_motion > TIMEOUT:
                    await client.publish(
                        command_topic(LIGHT),
                        envelope(command="set", params={"power": "off", "brightness": 0}),
                    )
                    light_on = False
                    print("[automation] keine Bewegung -> Licht aus")

        off_task = asyncio.create_task(auto_off())
        try:
            async for msg in client.messages:
                data = parse(msg.payload)
                if data.get("metric") == "motion" and data.get("value") == 1:
                    last_motion = time.time()
                    if not light_on:
                        await client.publish(
                            command_topic(LIGHT),
                            envelope(command="set", params={"power": "on", "brightness": 80}),
                        )
                        light_on = True
                        print("[automation] Bewegung -> Licht an")
        finally:
            off_task.cancel()


if __name__ == "__main__":
    asyncio.run(run_forever(_run, name="automation"))
