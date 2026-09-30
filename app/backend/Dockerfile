# Stage 1: Build 
FROM node:20-alpine AS builder
WORKDIR /app

# Upgrade global npm to patch upstream vulnerabilities in the base image
RUN npm install -g npm@latest

COPY package.json package-lock.json* ./

# Force a clean install and ensure tar is updated
RUN npm install && npm update tar

COPY server.js server.test.js ./

# Stage 2: Production (Minimal & Secure)
FROM node:20-alpine
WORKDIR /app

# Upgrade global npm here too just to be absolutely secure
RUN npm install -g npm@latest

RUN addgroup -S nodeapp && adduser -S nodeapp -G nodeapp

COPY --from=builder --chown=nodeapp:nodeapp /app /app

USER nodeapp
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:3000/health || exit 1

CMD ["node", "server.js"]