# Stage 1: Build using the latest Active LTS (Node 22)
FROM node:22-alpine AS builder
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install

COPY server.js server.test.js ./

# Stage 2: Production (Minimal & Secure)
FROM node:22-alpine
WORKDIR /app

# Security Best Practice: Create a non-root user
RUN addgroup -S nodeapp && adduser -S nodeapp -G nodeapp

COPY --from=builder --chown=nodeapp:nodeapp /app /app

USER nodeapp
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:3000/health || exit 1

CMD ["node", "server.js"]