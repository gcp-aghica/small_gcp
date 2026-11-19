# syntax=docker/dockerfile:1
# Один Dockerfile, несколько образов: --target app (calculations-api) и по target на каждую заглушку.
FROM python:3.12-slim AS base

COPY --from=ghcr.io/astral-sh/uv:0.12.23 /uv /usr/local/bin/uv

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /srv

# Сначала только зависимости: этот слой кэшируется, пока не меняется lock.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

RUN useradd --system --uid 10001 --no-create-home app

ARG GIT_SHA=unknown
ENV GIT_SHA=${GIT_SHA}
EXPOSE 8000

# Заглушки upstream-ов. Деплоятся руками (make upstreams), не через CD.
FROM base AS upstream
COPY upstreams ./upstreams
USER app

FROM upstream AS observation-store-api
CMD ["sh", "-c", "exec uvicorn upstreams.observation_store_api:app --host 0.0.0.0 --port ${PORT:-8000}"]

FROM upstream AS metadata-api
CMD ["sh", "-c", "exec uvicorn upstreams.metadata_api:app --host 0.0.0.0 --port ${PORT:-8000}"]

FROM upstream AS workspace-auth
CMD ["sh", "-c", "exec uvicorn upstreams.workspace_auth:app --host 0.0.0.0 --port ${PORT:-8000}"]

# Последним: docker build без --target собирает calculations-api.
FROM base AS app
COPY app ./app
USER app
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
