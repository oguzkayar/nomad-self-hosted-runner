import http from "node:http";
import os from "node:os";

const port = Number(process.env.PORT ?? 3000);
const serviceName = process.env.SERVICE_NAME ?? "weather-gateway";
const upstreamServiceName = process.env.UPSTREAM_SERVICE_NAME ?? "weather-service";
const upstreamBaseUrl = process.env.WEATHER_SERVICE_URL;
const requestTimeoutMs = Number(process.env.REQUEST_TIMEOUT_MS ?? 3000);

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  response.end(JSON.stringify(payload, null, 2));
}

async function fetchJson(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), requestTimeoutMs);

  try {
    const upstreamResponse = await fetch(url, {
      headers: { Accept: "application/json" },
      signal: controller.signal
    });

    const rawBody = await upstreamResponse.text();
    let body;

    try {
      body = JSON.parse(rawBody);
    } catch {
      body = { rawBody };
    }

    return {
      ok: upstreamResponse.ok,
      status: upstreamResponse.status,
      body
    };
  } finally {
    clearTimeout(timeout);
  }
}

const server = http.createServer(async (request, response) => {
  const requestUrl = new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`);

  if (request.method === "GET" && requestUrl.pathname === "/health") {
    return sendJson(response, 200, {
      status: "UP",
      service: serviceName,
      hostname: os.hostname(),
      upstreamServiceName,
      upstreamConfigured: Boolean(upstreamBaseUrl),
      timestamp: new Date().toISOString()
    });
  }

  const weatherMatch = requestUrl.pathname.match(/^\/api\/weather\/([^/]+)$/);
  if (request.method === "GET" && weatherMatch) {
    if (!upstreamBaseUrl) {
      return sendJson(response, 503, {
        error: "Upstream servis adresi henüz Consul üzerinden çözülemedi.",
        upstreamServiceName
      });
    }

    const city = weatherMatch[1];
    const upstreamUrl = `${upstreamBaseUrl.replace(/\/$/, "")}/weather/${encodeURIComponent(decodeURIComponent(city))}`;

    try {
      const upstreamResult = await fetchJson(upstreamUrl);

      if (!upstreamResult.ok) {
        return sendJson(response, 502, {
          error: "Weather service başarısız yanıt verdi.",
          upstreamServiceName,
          upstreamStatus: upstreamResult.status,
          upstreamBody: upstreamResult.body
        });
      }

      return sendJson(response, 200, {
        gateway: serviceName,
        discoveredBy: "Consul service catalog",
        upstreamServiceName,
        data: upstreamResult.body
      });
    } catch (error) {
      const isTimeout = error?.name === "AbortError";
      console.error(`[${serviceName}] ${upstreamServiceName} çağrısı başarısız:`, error);

      return sendJson(response, isTimeout ? 504 : 502, {
        error: isTimeout ? "Weather service zaman aşımına uğradı." : "Weather service erişilemez durumda.",
        upstreamServiceName,
        detail: error instanceof Error ? error.message : String(error)
      });
    }
  }

  return sendJson(response, 404, {
    error: "Endpoint bulunamadı.",
    availableEndpoints: ["GET /health", "GET /api/weather/:city"]
  });
});

server.listen(port, "0.0.0.0", () => {
  console.log(`[${serviceName}] 0.0.0.0:${port} adresinde dinleniyor.`);
  console.log(`[${serviceName}] upstream servis adı: ${upstreamServiceName}`);
  console.log(`[${serviceName}] Consul tarafından çözülen upstream adresi mevcut: ${Boolean(upstreamBaseUrl)}`);
});

function shutdown(signal) {
  console.log(`[${serviceName}] ${signal} alındı; sunucu kapatılıyor.`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 5000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
