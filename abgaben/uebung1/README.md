
## Schnellstart (Docker)

```bash
docker compose up --build
```

### Windows (PowerShell): Start + Funktionscheck

Der lange Check-Befehl prueft nur den Zustand (HTTP/MQTT/Logs/DB), startet aber
den Stack nicht. Deshalb zuerst immer starten:

```powershell
Set-Location "c:\Users\User\Documents\2 Universität\MA\03\HC\Uebung1\smart-home-demo"
docker compose up -d --build
```

Danach Funktionscheck (PowerShell-sicher, JSON per stdin):

```powershell
Set-Location "c:\Users\User\Documents\2 Universität\MA\03\HC\Uebung1\smart-home-demo"

Write-Host "=== compose ps ==="
docker compose ps

Write-Host "=== http checks ==="
$dash=(Invoke-WebRequest -Uri "http://localhost:8000" -UseBasicParsing).StatusCode
Write-Host "dashboard_status=$dash"
$rest=(Invoke-RestMethod -Uri "http://localhost:8001/status" -Method Get)
Write-Host ("rest_status=" + ($rest | ConvertTo-Json -Compress))

Write-Host "=== mqtt command tests ==="
'{"command":"set","params":{"power":"on","brightness":55}}' |
  docker compose exec -T broker mosquitto_pub -h broker -t home/command/light-living -s
'{"command":"set","params":{"power":"on"}}' |
  docker compose exec -T broker mosquitto_pub -h broker -t home/command/plug-kitchen -s

Write-Host "=== recent service logs ==="
docker compose logs --no-color --tail 30 smart-light automation adapter rest-device

Write-Host "=== cloud db row count ==="
docker compose exec -T cloud-sync python -c "import sqlite3; conn=sqlite3.connect('/data/cloud.db'); print('telemetry_rows=' + str(conn.execute('select count(*) from telemetry').fetchone()[0]))"
```

Stoppen:

```powershell
docker compose down
```

Danach:

- Dashboard: <http://localhost:8000>
- Fremdgerät direkt: <http://localhost:8001/status>

Das Fremdgerät schalten (Adapter leitet das Kommando als HTTP weiter):

```bash
mosquitto_pub -h localhost -t home/command/plug-kitchen \
  -m '{"command":"set","params":{"power":"on"}}'
```

## Lokaler Start ohne Docker

```bash
pip install -r requirements.txt
mosquitto -c mosquitto/mosquitto.conf &        # Broker

python -m devices.temp_sensor &
python -m devices.motion_sensor &
python -m devices.smart_light &
python -m services.automation &
python -m services.cloud_sync &
uvicorn rest_device.service:app --port 8001 &
python -m rest_device.adapter &
uvicorn services.dashboard:app --port 8000
```


## Demo-Skript für den Vortrag

1. `docker compose up` – alle Container starten, Dashboard öffnen.
2. Zeigen, wie Telemetrie live erscheint (Tageskurve der Temperatur).
3. Bewegung triggert die Automation → Lampe schaltet im Dashboard auf `on`.
4. Adapter demonstrieren: `mosquitto_pub` schaltet das REST-Fremdgerät.
5. Einen Container stoppen (`docker compose stop temp-sensor`) → im Dashboard
   wird das Gerät über das Last-Will-Topic `offline` (Fehlertoleranz).
6. Die aggregierte Historie zeigen: `sqlite3 data/cloud.db "SELECT * FROM
   telemetry ORDER BY ts DESC LIMIT 10;"` (Edge → Cloud).
