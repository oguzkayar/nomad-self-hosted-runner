# syntax=docker/dockerfile:1

ARG NODE_VERSION=20

FROM node:${NODE_VERSION}-alpine AS base
WORKDIR /app
ENV NODE_ENV=production

# Build with:
# docker build --target weather-service -t nomad-weather-service:1.0 .
FROM base AS weather-service

COPY --chown=node:node weather-service/package.json ./package.json
COPY --chown=node:node weather-service/src ./src

ENV PORT=3001 \
    SERVICE_NAME=weather-service

EXPOSE 3001

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:' + process.env.PORT + '/health').then(response => process.exit(response.ok ? 0 : 1)).catch(() => process.exit(1));"

USER node
CMD ["node", "src/server.js"]

# Build with:
# docker build --target weather-gateway -t nomad-weather-gateway:1.0 .
FROM base AS weather-gateway

COPY --chown=node:node weather-gateway/package.json ./package.json
COPY --chown=node:node weather-gateway/src ./src

ENV PORT=3000 \
    SERVICE_NAME=weather-gateway \
    UPSTREAM_SERVICE_NAME=weather-service \
    REQUEST_TIMEOUT_MS=3000

EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:' + process.env.PORT + '/health').then(response => process.exit(response.ok ? 0 : 1)).catch(() => process.exit(1));"

USER node
CMD ["node", "src/server.js"]
