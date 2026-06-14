FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV PYTHONUNBUFFERED=1 MQTT_HOST=broker
# Das konkrete Kommando setzt docker-compose je Dienst.
CMD ["python", "-c", "print('Bitte command in docker-compose setzen')"]
