"""Adapter zwischen dem HTTP-only Fremdgeraet und dem MQTT-Bus.

Klassisches Adapter-/Anti-Corruption-Layer-Muster und der Kern der
Interoperabilitaet im Demonstrator:
  - pollt periodisch GET /status und uebersetzt das Ergebnis in den einheitlichen
    MQTT-Envelope (Telemetrie + retained Zustand),
  - abonniert MQTT-Kommandos und leitet sie als POST /command weiter.

Dadurch erscheint ein protokollfremdes Geraet fuer den Rest des Systems wie
jedes native MQTT-Geraet -- neue Protokolle erfordern nur einen neuen Adapter
(Erweiterbarkeit), nicht aenderungen am Kern.
"""
from __future__ import annotations

import asyncio
import os

import httpx

from common.mqtt import client_for, run_forever
from common.topics import (
    availability_topic,
    command_topic,
    envelope,
    parse,
    state_topic,
    telemetry_topic,
)

DEVICE = "plug-kitchen"
REST_URL = os.environ.get("PLUG_URL", "http://localhost:8001")


async def _poll(client, http):
    while True:
        try:
            data = (await http.get(f"{REST_URL}/status")).json()
            await client.publish(
                telemetry_topic(DEVICE, "power_watt"),
                envelope(device_id=DEVICE, metric="power_watt", value=data["watt"], unit="W"),
                qos=1,
            )
            await client.publish(
                state_topic(DEVICE),
                envelope(device_id=DEVICE, power=data["power"]),
                qos=1,
                retain=True,
            )
        except Exception as exc:
            print(f"[adapter] REST nicht erreichbar: {exc}")
        await asyncio.sleep(5)


async def _commands(client, http):
    await client.subscribe(command_topic(DEVICE))
    async for msg in client.messages:
        cmd = parse(msg.payload)
        if cmd.get("command") == "set":
            power = cmd.get("params", {}).get("power")
            try:
                await http.post(f"{REST_URL}/command", json={"power": power})
                print(f"[adapter] Kommando weitergeleitet: power={power}")
            except Exception as exc:
                print(f"[adapter] Weiterleitung fehlgeschlagen: {exc}")


async def _run():
    async with client_for(DEVICE) as client, httpx.AsyncClient(timeout=5) as http:
        await client.publish(availability_topic(DEVICE), b"online", qos=1, retain=True)
        print(f"[adapter] aktiv: {DEVICE} <-> {REST_URL}")
        await asyncio.gather(_poll(client, http), _commands(client, http))


if __name__ == "__main__":
    asyncio.run(run_forever(_run, name=f"adapter-{DEVICE}"))
