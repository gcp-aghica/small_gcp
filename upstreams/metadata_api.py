"""Заглушка Metadata API (metadata-store): PPP и инфляция для цепочек."""

from typing import Any

from fastapi import Depends, FastAPI

from upstreams._common import health, require_bearer

app = FastAPI(title="metadata-api (sandbox stub)")
app.get("/health")(health)

_auth = [Depends(require_bearer("METADATA_API_BEARER_TOKEN"))]


@app.get("/v1/ppp", dependencies=_auth)
def ppp(country: str) -> dict[str, Any]:
    return {"country": country, "ppp": 1.0}


@app.get("/v1/inflation", dependencies=_auth)
def inflation(country: str, year: int) -> dict[str, Any]:
    return {"country": country, "year": year, "rate": 0.02}
