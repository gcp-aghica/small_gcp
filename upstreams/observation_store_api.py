"""Заглушка observation-store-api.

Как настоящий: отдельный сервис со своим деплоем (руками, make upstreams), владеет секретом
observation-api-token и читает его как OBSERVATION_STORE_API_BEARER_TOKEN. calculations-api
читает тот же секрет под тем же именем и шлёт его в Authorization.
"""

from typing import Any

from fastapi import Depends, FastAPI

from upstreams._common import health, require_bearer

app = FastAPI(title="observation-store-api (sandbox stub)")
app.get("/health")(health)


@app.get("/v1/series", dependencies=[Depends(require_bearer("OBSERVATION_STORE_API_BEARER_TOKEN"))])
def series(site_id: str) -> dict[str, Any]:
    return {
        "site_id": site_id,
        "points": [
            {"date": "2026-07-01", "value": 24.5},
            {"date": "2026-07-02", "value": 31.0},
            {"date": "2026-07-03", "value": 28.2},
        ],
    }
