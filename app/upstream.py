"""Клиент Observation Store API (аналог routers/_shared.py в calculations-api)."""

from collections.abc import Iterator
from typing import Annotated, Any

import httpx
from fastapi import Depends, HTTPException, status

from app.settings import Settings, get_settings


class UpstreamError(HTTPException):
    """Ошибка upstream отдаётся пользователю как 502, а не как его собственный 401."""

    def __init__(self, service: str, reason: str) -> None:
        super().__init__(status.HTTP_502_BAD_GATEWAY, f"{service}: {reason}")


def observation_client(
    settings: Annotated[Settings, Depends(get_settings)],
) -> Iterator[httpx.Client]:
    if not settings.observation_store_api_base_url:
        raise UpstreamError("observation-store-api", "OBSERVATION_STORE_API_BASE_URL is not set")
    with httpx.Client(
        base_url=settings.observation_store_api_base_url,
        headers={"Authorization": f"Bearer {settings.observation_store_api_bearer_token}"},
        timeout=10,
    ) as client:
        yield client


def get_series(client: httpx.Client, site_id: str) -> dict[str, Any]:
    try:
        resp = client.get("/v1/series", params={"site_id": site_id})
    except httpx.HTTPError as exc:
        raise UpstreamError("observation-store-api", type(exc).__name__) from exc
    if resp.status_code != 200:
        raise UpstreamError("observation-store-api", f"HTTP {resp.status_code}")
    return resp.json()
