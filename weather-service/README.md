# Weather Service

Basit ve harici API anahtarı gerektirmeyen hava durumu backend'idir.

## Endpointler

- `GET /health`
- `GET /weather/:city`

## Yerel çalıştırma

```bash
npm start
curl http://localhost:3001/weather/Ankara
```

## Docker

```bash
docker build -t nomad-weather-service:1.0 .
docker run --rm -p 3001:3001 nomad-weather-service:1.0
```
