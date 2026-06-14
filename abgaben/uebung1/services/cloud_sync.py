"""Cloud-Sync (Edge -> 'Cloud').

Abonniert die gesamte Telemetrie und schreibt sie in eine SQLite-Datenbank, die
hier stellvertretend fuer einen Cloud-Speicher steht. Das zeigt die
Edge/Cloud-Trennung: lokale, latenzkritische Logik laeuft in der Automation am
Edge; die zentrale Historie/Aggregation uebernimmt dieser separate Dienst.
"""
from __future__ import annotations

import asyncio
import os
import sqlite3

from common.mqtt import client_for, run_forever
from common.topics import ALL_TELEMETRY, availability_topic, parse

SERVICE = "cloud-sync"
DB = os.environ.get("CLOUD_DB", "cloud.db")


def _init() -> sqlite3.Connection:
    con = sqlite3.connect(DB)
    con.execute(
        "CREATE TABLE IF NOT EXISTS telemetry "
        "(ts REAL, device_id TEXT, metric TEXT, value REAL, unit TEXT)"
    )
    con.commit()
    return con


async def _run():
    con = _init()
    async with client_for(SERVICE) as client:
        await client.publish(availability_topic(SERVICE), b"online", qos=1, retain=True)
        await client.subscribe(ALL_TELEMETRY)
        print(f"[cloud] Aggregation aktiv -> {DB}")
        async for msg in client.messages:
            d = parse(msg.payload)
            try:
                con.execute(
                    "INSERT INTO telemetry VALUES (?,?,?,?,?)",
                    (d["ts"], d["device_id"], d["metric"], float(d["value"]), d.get("unit", "")),
                )
                con.commit()
            except (KeyError, ValueError, TypeError) as exc:
                print(f"[cloud] verwerfe ungueltige Nachricht: {exc}")


if __name__ == "__main__":
    asyncio.run(run_forever(_run, name="cloud-sync"))
