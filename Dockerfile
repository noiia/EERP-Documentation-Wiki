# ── Stage 1: build ──────────────────────────────────────────────────────────
FROM python:3.13-alpine AS builder

WORKDIR /build

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY mkdocs.yml .
COPY docs/ docs/

RUN mkdocs build --strict

# ── Stage 2: serve ──────────────────────────────────────────────────────────
FROM nginx:1.31.1-alpine

COPY --from=builder /build/site /usr/share/nginx/html

# Clean default config and replace with minimal one
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost/health || exit 1
