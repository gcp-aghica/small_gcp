"""Проверка JWT пользователя по JWKS Workspace Supabase (как в calculations-api)."""

from functools import lru_cache
from typing import Annotated, Any

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.settings import Settings, get_settings

# auto_error=False: без заголовка получаем None и сами отдаём 401 (а не 403 по умолчанию).
bearer = HTTPBearer(auto_error=False)

AUDIENCE = "authenticated"  # aud в токенах Supabase Auth
ALGORITHMS = ["RS256", "ES256"]


@lru_cache
def jwks_client(url: str) -> jwt.PyJWKClient:
    return jwt.PyJWKClient(url, cache_keys=True, lifespan=600)


def _unauthorized() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Unauthorized",
        headers={"WWW-Authenticate": "Bearer"},
    )


def current_user(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, Any]:
    if creds is None:
        raise _unauthorized()
    try:
        key = jwks_client(settings.jwks_url).get_signing_key_from_jwt(creds.credentials)
        return jwt.decode(creds.credentials, key.key, algorithms=ALGORITHMS, audience=AUDIENCE)
    except jwt.PyJWKClientConnectionError as exc:
        # JWKS недоступен: это наша проблема, а не пользователя.
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "JWKS unavailable") from exc
    except jwt.PyJWTError as exc:
        raise _unauthorized() from exc
