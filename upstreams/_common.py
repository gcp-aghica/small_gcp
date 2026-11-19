"""Общее для заглушек upstream-сервисов."""

import os
import secrets
from collections.abc import Callable
from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

bearer = HTTPBearer(auto_error=False)


def env(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, f"{name} is not set")
    return value


def require_bearer(env_name: str) -> Callable[..., None]:
    """Зависимость FastAPI: Authorization: Bearer <значение env_name>."""

    def check(creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]) -> None:
        expected = env(env_name)
        if creds is None or not secrets.compare_digest(creds.credentials, expected):
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Unauthorized")

    return check


def health() -> dict[str, str]:
    return {"status": "ok", "git_sha": os.environ.get("GIT_SHA", "unknown")}
