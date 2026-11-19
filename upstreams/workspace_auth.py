"""Заглушка Workspace Supabase Auth: только JWKS.

Публичный ключ выводится из JWT_PRIVATE_KEY (секрет workspace-jwt-private-key).
Тестовые токены выпускает scripts/mint_jwt.py тем же ключом.
"""

import json
from functools import lru_cache
from typing import Any

import jwt
from cryptography.hazmat.primitives import serialization
from fastapi import FastAPI

from upstreams._common import env, health

KID = "sandbox-1"

app = FastAPI(title="workspace-auth (sandbox stub)")
app.get("/health")(health)


@lru_cache
def _jwks(pem: str) -> dict[str, Any]:
    public_key = serialization.load_pem_private_key(pem.encode(), password=None).public_key()
    jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(public_key))  # type: ignore[arg-type]
    jwk.update({"kid": KID, "alg": "RS256", "use": "sig"})
    return {"keys": [jwk]}


@app.get("/auth/v1/.well-known/jwks.json")
def jwks() -> dict[str, Any]:
    return _jwks(env("JWT_PRIVATE_KEY"))
