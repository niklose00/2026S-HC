"""'Fremdgeraet': ein simulierter Smart-Stecker, der NUR HTTP/JSON spricht.

Es kennt MQTT nicht -- es steht stellvertretend fuer ein Geraet mit fremdem
Protokoll/Datenmodell (Heterogenitaet). Die Anbindung an die Infrastruktur
uebernimmt ausschliesslich der Adapter (adapter.py).

Start (lokal):  uvicorn rest_device.service:app --port 8001
"""
from __future__ import annotations

import random
import time

from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="Legacy Smart Plug (HTTP only)")

_state = {"power": "off", "watt": 0.0}


class Command(BaseModel):
    power: str | None = None


@app.get("/status")
def status():
    # Eigenes, vom MQTT-Envelope abweichendes Datenmodell -> Heterogenitaet.
    _state["watt"] = round(random.uniform(40, 120), 1) if _state["power"] == "on" else 0.0
    return {"device_id": "plug-kitchen", "ts": time.time(), **_state}


@app.post("/command")
def command(cmd: Command):
    if cmd.power in ("on", "off"):
        _state["power"] = cmd.power
    return {"ok": True, **_state}
