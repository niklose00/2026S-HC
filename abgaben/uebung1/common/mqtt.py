"""MQTT-Hilfsfunktionen.

Stellt einen vorkonfigurierten Client mit "Last Will and Testament" (LWT) bereit
und eine Reconnect-Schleife. Beides adressiert direkt Fehlertoleranz/Robustheit:

- LWT: Bricht die Verbindung eines Geraets unerwartet ab, veroeffentlicht der
  Broker automatisch "offline" auf dem availability-Topic. Andere Komponenten
  erkennen den Ausfall, ohne dass das Geraet sich selbst abmelden konnte.
- run_forever: Faengt Verbindungsfehler ab und startet die Komponente neu.
"""
from __future__ import annotations

import asyncio
import os

import aiomqtt

from .topics import availability_topic

BROKER = os.environ.get("MQTT_HOST", "localhost")
PORT = int(os.environ.get("MQTT_PORT", "1883"))


def client_for(device_id: str) -> aiomqtt.Client:
    """Erzeugt einen MQTT-Client mit retained Last-Will fuer dieses Geraet."""
    will = aiomqtt.Will(
        topic=availability_topic(device_id),
        payload=b"offline",
        qos=1,
        retain=True,
    )
    return aiomqtt.Client(
        hostname=BROKER, port=PORT, identifier=device_id, will=will
    )


async def run_forever(main_coro, *, name: str, delay: float = 3.0) -> None:
    """Fuehrt main_coro aus und startet es bei MQTT-Verbindungsfehlern neu."""
    while True:
        try:
            await main_coro()
        except aiomqtt.MqttError as exc:
            print(f"[{name}] Verbindung verloren ({exc}); neuer Versuch in {delay}s")
            await asyncio.sleep(delay)
