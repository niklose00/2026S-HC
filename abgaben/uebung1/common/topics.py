"""Zentrale Definition aller MQTT-Topics und des Nachrichten-Envelopes.

Eine einzige Quelle der Wahrheit fuer das Nachrichtenformat. Alle Komponenten
importieren von hier -- so entstehen klar definierte Schnittstellen, ohne dass
die Komponenten einander direkt kennen muessen (lose Kopplung).

Topic-Schema:
    home/telemetry/{device_id}/{metric}   Messwerte (Sensoren -> Bus)
    home/command/{device_id}              Steuerbefehle (Bus -> Aktoren)
    home/state/{device_id}                Aktueller Zustand (retained)
    home/availability/{device_id}         "online"/"offline" (retained, via LWT)
"""
from __future__ import annotations

import json
import time

BASE = "home"


def telemetry_topic(device_id: str, metric: str) -> str:
    return f"{BASE}/telemetry/{device_id}/{metric}"


def command_topic(device_id: str) -> str:
    return f"{BASE}/command/{device_id}"


def state_topic(device_id: str) -> str:
    return f"{BASE}/state/{device_id}"


def availability_topic(device_id: str) -> str:
    return f"{BASE}/availability/{device_id}"


# Wildcards fuer Abonnenten (Automation, Dashboard, Cloud-Sync)
ALL_TELEMETRY = f"{BASE}/telemetry/#"
ALL_STATE = f"{BASE}/state/#"
ALL_AVAILABILITY = f"{BASE}/availability/#"


def envelope(**fields) -> bytes:
    """Baut einen JSON-Envelope mit Zeitstempel und gibt ihn als bytes zurueck."""
    return json.dumps({"ts": time.time(), **fields}).encode()


def parse(payload: bytes) -> dict:
    """Liest einen JSON-Envelope zurueck in ein dict."""
    return json.loads(payload.decode())
