# Stage 1: install production dependencies only (reproducible via lockfile)
FROM node:22-alpine AS builder
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY server.js ./

# Stage 2: minimal runtime image (no tests, no dev tooling, no npm cache)
FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production

# Security best practice: run as a dedicated non-root user
RUN addgroup -S nodeapp && adduser -S nodeapp -G nodeapp

COPY --from=builder --chown=nodeapp:nodeapp /app/node_modules ./node_modules
COPY --from=builder --chown=nodeapp:nodeapp /app/server.js ./server.js
COPY --chown=nodeapp:nodeapp package.json ./

USER nodeapp
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:3000/metrics || exit 1

CMD ["node", "server.js"]
