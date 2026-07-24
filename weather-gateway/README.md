# Weather Gateway

İstemcinin çağırdığı giriş backend'idir. Nomad job dosyasındaki Consul Template, `weather-service` adını çözer ve sonucu `WEATHER_SERVICE_URL` ortam değişkenine yazar.

## Endpointler

- `GET /health`
- `GET /api/weather/:city`

## Yerel çalıştırma

Önce weather-service'i çalıştırın, ardından:

```bash
WEATHER_SERVICE_URL=http://localhost:3001 npm start
curl http://localhost:3000/api/weather/Ankara
```

## Docker

```bash
docker build -t nomad-weather-gateway:1.0 .
docker run --rm -p 3000:3000 \
  -e WEATHER_SERVICE_URL=http://host.docker.internal:3001 \
  nomad-weather-gateway:1.0
```
