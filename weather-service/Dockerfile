FROM node:20-alpine

WORKDIR /app

COPY package.json ./
COPY src ./src

ENV NODE_ENV=production
ENV PORT=3001

EXPOSE 3001

USER node

CMD ["npm", "start"]
