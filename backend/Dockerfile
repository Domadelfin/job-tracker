# syntax=docker/dockerfile:1
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app

# Pull in OS security patches the base image doesn't have yet
# (e.g. CVE-2026-4738 in zlib, flagged CRITICAL by ECR scanning).
RUN apk upgrade --no-cache

# Amazon RDS CA bundle so TLS connections to RDS can be verified.
ADD --chmod=644 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /app/certs/rds-global-bundle.pem

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

# Run as the unprivileged "node" user that ships with the image, not root.
USER node
EXPOSE 4000
CMD ["node", "src/server.js"]
