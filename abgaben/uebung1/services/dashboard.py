"""Dashboard / API.

Abonniert im Hintergrund den MQTT-Bus, haelt den letzten bekannten Zustand aller
Geraete im Speicher und stellt ihn ueber HTTP bereit:
  GET /            schlanke Live-Statusseite (HTML, pollt /api/state)
  GET /api/state   aktueller Zustand als JSON

Start (lokal):  uvicorn services.dashboard:app --port 8000
"""
from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager

import aiomqtt
from fastapi import FastAPI
from fastapi.responses import HTMLResponse

from common.mqtt import BROKER, PORT
from common.topics import ALL_AVAILABILITY, ALL_STATE, ALL_TELEMETRY, parse

STATE: dict[str, dict] = {}


async def _listen():
    while True:
        try:
            async with aiomqtt.Client(hostname=BROKER, port=PORT, identifier="dashboard") as client:
                for topic in (ALL_TELEMETRY, ALL_STATE, ALL_AVAILABILITY):
                    await client.subscribe(topic)
                async for msg in client.messages:
                    topic = str(msg.topic)
                    if topic.startswith("home/availability/"):
                        dev = topic.split("/")[-1]
                        STATE.setdefault(dev, {})["availability"] = msg.payload.decode()
                    else:
                        d = parse(msg.payload)
                        dev = d.get("device_id", topic)
                        STATE.setdefault(dev, {}).update(d)
        except aiomqtt.MqttError:
            await asyncio.sleep(3)


@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(_listen())
    yield
    task.cancel()


app = FastAPI(title="Smart-Home Dashboard", lifespan=lifespan)


@app.get("/api/state")
def api_state():
    return STATE


@app.get("/", response_class=HTMLResponse)
def index():
    return _PAGE


_PAGE = """<!doctype html>
<html lang="de"><head><meta charset="utf-8">
<title>Smart-Home Dashboard</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
 body{font-family:system-ui,Arial,sans-serif;margin:0;background:#0f1115;color:#e8e8ea}
 header{padding:16px 24px;border-bottom:1px solid #23262e;font-weight:600}
 #grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:14px;padding:24px}
 .card{background:#181b21;border:1px solid #242832;border-radius:12px;padding:16px}
 .dev{font-weight:600;margin-bottom:10px;display:flex;justify-content:space-between;align-items:center}
 .row{display:flex;justify-content:space-between;font-size:14px;color:#aab1c0;margin:4px 0}
 .badge{font-size:12px;padding:2px 9px;border-radius:999px;background:#242832}
 .on{background:#143d2b;color:#5ddc9c}.off{background:#3d1717;color:#e0696a}
 .empty{padding:24px;color:#777}
</style></head>
<body>
<header>Smart-Home Dashboard &middot; Live</header>
<div id="grid"></div>
<div id="empty" class="empty">Warte auf Daten vom Bus &hellip;</div>
<script>
const SKIP=['device_id','ts','availability','note','unit','metric'];
async function tick(){
 try{
  const s=await (await fetch('/api/state')).json();
  const keys=Object.keys(s);
  document.getElementById('empty').style.display=keys.length?'none':'block';
  const g=document.getElementById('grid');g.innerHTML='';
  for(const dev of keys.sort()){
   const d=s[dev], av=d.availability||'?';
   const rows=Object.entries(d).filter(([k])=>!SKIP.includes(k)).map(([k,v])=>{
     const label=(d.metric&&k==='value')?d.metric:k;
     const unit=(k==='value'&&d.unit)?(' '+d.unit):'';
     return `<div class="row"><span>${label}</span><span>${v}${unit}</span></div>`;
   }).join('');
   g.innerHTML+=`<div class="card"><div class="dev"><span>${dev}</span>`+
     `<span class="badge ${av==='online'?'on':'off'}">${av}</span></div>${rows}</div>`;
  }
 }catch(e){}
}
setInterval(tick,2000);tick();
</script></body></html>"""
