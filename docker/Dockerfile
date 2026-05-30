# =============================================
# Stage 1: Build frontend
# =============================================
FROM node:22-alpine AS frontend-builder

WORKDIR /app

# Copy workspace config first (Docker layer caching)
COPY package.json ./
COPY apps/frontend/package.json ./apps/frontend/
RUN npm install --no-audit --no-fund

# Copy frontend source (only changes → rebuilds frontend)
COPY apps/frontend/ ./apps/frontend/
RUN npm run build:frontend


# =============================================
# Stage 2: Build backend
# =============================================
FROM node:22-alpine AS backend-builder

WORKDIR /app

# Copy workspace config first
COPY package.json ./
COPY apps/backend/package.json ./apps/backend/
RUN npm install --no-audit --no-fund

# Copy backend source (only changes → rebuilds backend)
COPY apps/backend/ ./apps/backend/
RUN npm run build --workspace=apps/backend && \
    npm prune --production --workspace=apps/backend


# =============================================
# Stage 3: Production
# =============================================
FROM node:22-alpine AS production

WORKDIR /app

# Create data directory for SQLite
RUN mkdir -p /app/apps/backend/data

# Copy workspace config first
COPY package.json ./
COPY apps/backend/package.json ./apps/backend/
RUN npm install --omit=dev --no-audit --no-fund

# Copy built artifacts (cheap — no npm install)
COPY --from=backend-builder /app/apps/backend/dist ./apps/backend/dist
COPY --from=frontend-builder /app/apps/frontend/dist ./apps/frontend/dist

EXPOSE 3000

CMD ["node", "apps/backend/dist/main.js"]
