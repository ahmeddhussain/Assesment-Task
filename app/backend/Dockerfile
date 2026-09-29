# Stage 1: Build 
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json* ./
# Best Practice: Use npm ci for reproducible builds
RUN npm install 
COPY server.js server.test.js ./

# Stage 2: Production (Minimal & Secure)
FROM node:20-alpine
WORKDIR /app

RUN addgroup -S nodeapp && adduser -S nodeapp -G nodeapp

# Copy node_modules and app files from builder
COPY --from=builder --chown=nodeapp:nodeapp /app /app

USER nodeapp
EXPOSE 3000

# Healthcheck hits the /health endpoint
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:3000/health || exit 1

CMD ["node", "server.js"]