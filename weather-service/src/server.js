import http from "node:http";
import os from "node:os";

const port = Number(process.env.PORT ?? 3001);
const serviceName = process.env.SERVICE_NAME ?? "weather-service";

const knownCities = {
  ankara: { temperatureC: 23, condition: "Parçalı bulutlu", humidity: 41, windKph: 13 },
  istanbul: { temperatureC: 26, condition: "Bulutlu", humidity: 66, windKph: 18 },
  izmir: { temperatureC: 31, condition: "Güneşli", humidity: 48, windKph: 16 },
  antalya: { temperatureC: 34, condition: "Güneşli", humidity: 55, windKph: 11 },
  rodos: { temperatureC: 32, condition: "Açık", humidity: 52, windKph: 20 }
};

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  response.end(JSON.stringify(payload, null, 2));
}

function normalizeCity(value) {
  return decodeURIComponent(value ?? "")
    .trim()
    .toLocaleLowerCase("tr-TR");
}

function createFallbackWeather(city) {
  const hash = [...city].reduce((sum, character) => sum + character.codePointAt(0), 0);
  const conditions = ["Açık", "Parçalı bulutlu", "Bulutlu", "Hafif rüzgârlı"];

  return {
    temperatureC: 15 + (hash % 19),
    condition: conditions[hash % conditions.length],
    humidity: 35 + (hash % 41),
    windKph: 5 + (hash % 21)
  };
}

const server = http.createServer((request, response) => {
  const requestUrl = new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`);

  if (request.method === "GET" && requestUrl.pathname === "/health") {
    return sendJson(response, 200, {
      status: "UP",
      service: serviceName,
      hostname: os.hostname(),
      timestamp: new Date().toISOString()
    });
  }

  const weatherMatch = requestUrl.pathname.match(/^\/weather\/([^/]+)$/);
  if (request.method === "GET" && weatherMatch) {
    const normalizedCity = normalizeCity(weatherMatch[1]);

    if (!normalizedCity) {
      return sendJson(response, 400, { error: "Şehir adı boş olamaz." });
    }

    const weather = knownCities[normalizedCity] ?? createFallbackWeather(normalizedCity);

    return sendJson(response, 200, {
      city: normalizedCity.charAt(0).toLocaleUpperCase("tr-TR") + normalizedCity.slice(1),
      ...weather,
      source: serviceName,
      instance: os.hostname(),
      observedAt: new Date().toISOString()
    });
  }

  return sendJson(response, 404, {
    error: "Endpoint bulunamadı.",
    availableEndpoints: ["GET /health", "GET /weather/:city"]
  });
});

server.listen(port, "0.0.0.0", () => {
  console.log(`[${serviceName}] 0.0.0.0:${port} adresinde dinleniyor.`);
});

function shutdown(signal) {
  console.log(`[${serviceName}] ${signal} alındı; sunucu kapatılıyor.`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 5000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
