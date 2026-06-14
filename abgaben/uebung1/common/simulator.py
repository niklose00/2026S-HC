"""Deterministische Simulation des Geraeteverhaltens.

Erzeugt realistische Messwerte rein rechnerisch -- ohne externen Dienst und ohne
KI zur Laufzeit:

- Temperatur folgt einer Tageskurve (Minimum nachts, Maximum am Nachmittag) mit
  leichter Traegheit, sodass sich aufeinanderfolgende Werte glatt entwickeln.
- Bewegung folgt einem tageszeitabhaengigen Belegungsmuster mit kurzen
  Aktivitaetsphasen (wer sich gerade bewegt hat, bewegt sich eher weiter).
- Luftfeuchte schwankt als sanfter Random Walk um einen Mittelwert.

Die Funktionen bekommen die bisherige Historie und die simulierte Tageszeit und
liefern den naechsten Messwert zurueck.
"""
from __future__ import annotations

import math
import random


def _temperature(sim_hour: float, history: list[float]) -> float:
    # Tageskurve: Tiefpunkt gegen 3 Uhr, Hochpunkt gegen 15 Uhr (Mittel 19, +/-4)
    target = 19 + 4 * math.sin((sim_hour - 9) / 24 * 2 * math.pi)
    if history:
        last = history[-1]
        # Traegheit: nur ein Teilschritt Richtung Zielkurve, plus kleines Rauschen
        value = last + 0.3 * (target - last) + random.uniform(-0.2, 0.2)
    else:
        value = target + random.uniform(-0.2, 0.2)
    return round(value, 1)


def _humidity(history: list[float]) -> float:
    last = history[-1] if history else 45.0
    value = last + random.uniform(-1.5, 1.5)
    return round(min(70.0, max(30.0, value)), 1)


def _motion(sim_hour: float, history: list[float]) -> int:
    daytime = 7 <= sim_hour <= 23
    p = 0.25 if daytime else 0.03
    # Persistenz: laufende Bewegung dauert eher an
    if history and history[-1] == 1:
        p = min(0.85, p + 0.5)
    return 1 if random.random() < p else 0


def next_reading(role: str, sim_hour: float, history: list[float]):
    """Liefert den naechsten Messwert fuer die gegebene Geraeterolle."""
    if role == "temperature":
        return _temperature(sim_hour, history)
    if role == "humidity":
        return _humidity(history)
    if role == "motion":
        return _motion(sim_hour, history)
    return round(random.random(), 3)
