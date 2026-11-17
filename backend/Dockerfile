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
# Permissions set explicitly: `ADD --chmod=644` also applied 644 to the created
# /app/certs directory, and without the execute bit the non-root user couldn't
# open the file (EACCES on ECS).
ADD https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /app/certs/rds-global-bundle.pem
RUN chmod 755 /app/certs && chmod 644 /app/certs/rds-global-bundle.pem

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

# Run as the unprivileged "node" user that ships with the image, not root.
USER node
# Fail the build (not the deploy) if the app user can't read the CA bundle.
RUN test -r /app/certs/rds-global-bundle.pem
EXPOSE 4000
CMD ["node", "src/server.js"]
