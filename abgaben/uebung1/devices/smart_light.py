"""Smart-Lampe (simulierter Aktor).

Hoert auf Kommandos (home/command/light-living), aktualisiert ihren Zustand und
veroeffentlicht ihn retained (home/state/light-living), sodass spaeter
verbundene Komponenten sofort den letzten Stand sehen.
"""
from __future__ import annotations

import asyncio

from common.mqtt import client_for, run_forever
from common.topics import availability_topic, command_topic, envelope, parse, state_topic

DEVICE = "light-living"


async def _run():
    state = {"power": "off", "brightness": 0}
    async with client_for(DEVICE) as client:
        await client.publish(availability_topic(DEVICE), b"online", qos=1, retain=True)
        await client.publish(
            state_topic(DEVICE), envelope(device_id=DEVICE, **state), qos=1, retain=True
        )
        await client.subscribe(command_topic(DEVICE))
        print(f"[{DEVICE}] online (Aktor), warte auf Kommandos")
        async for msg in client.messages:
            cmd = parse(msg.payload)
            if cmd.get("command") == "set":
                state.update(cmd.get("params", {}))
                await client.publish(
                    state_topic(DEVICE),
                    envelope(device_id=DEVICE, **state),
                    qos=1,
                    retain=True,
                )
                print(f"[{DEVICE}] neuer Zustand: {state}")


if __name__ == "__main__":
    asyncio.run(run_forever(_run, name=DEVICE))
