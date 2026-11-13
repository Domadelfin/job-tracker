# syntax=docker/dockerfile:1
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app

# Amazon RDS CA bundle so TLS connections to RDS can be verified.
ADD --chmod=644 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /app/certs/rds-global-bundle.pem

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

# Run as the unprivileged "node" user that ships with the image, not root.
USER node
EXPOSE 4000
CMD ["node", "src/server.js"]
