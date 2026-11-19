import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Annotated, Any

import httpx
from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.auth import current_user
from app.settings import get_settings, split_origins
from app.upstream import get_series, observation_client


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    # Без обязательных переменных падаем при старте: Cloud Run не переключит трафик.
    get_settings()
    yield


app = FastAPI(title="calculations-api (sandbox)", lifespan=lifespan)

# Middleware добавляется при импорте, до lifespan, поэтому CORS_ORIGINS читаем из env напрямую:
# импорт не должен падать на неполном конфиге (обязательные поля проверяет lifespan).
app.add_middleware(
    CORSMiddleware,
    allow_origins=split_origins(os.environ.get("CORS_ORIGINS", "")),
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "git_sha": get_settings().git_sha}


@app.get("/risk/site")
def risk_site(
    site_id: str,
    user: Annotated[dict[str, Any], Depends(current_user)],
    client: Annotated[httpx.Client, Depends(observation_client)],
) -> dict[str, Any]:
    series = get_series(client, site_id)
    values = [p["value"] for p in series.get("points", [])]
    return {
        "site_id": site_id,
        "user": user.get("sub"),
        "points": len(values),
        "max_temperature": max(values) if values else None,
    }
