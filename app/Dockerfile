# VULN-IaC-001: Using non-specific tag instead of pinned digest
FROM node:18

# VULN-IaC-002: Running as root (no USER directive)
WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY src/ ./src/

# VULN-IaC-003: Exposing unnecessary ports
EXPOSE 3000 9229

# VULN-IaC-004: No HEALTHCHECK defined
# VULN-IaC-005: No read-only filesystem

ENV NODE_ENV=production
CMD ["node", "src/server.js"]
