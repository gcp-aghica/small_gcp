import os
import secrets
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

app = FastAPI(title="demo-api")

# auto_error=False: без заголовка получаем None и сами отдаём 401 (а не 403 по умолчанию).
bearer = HTTPBearer(auto_error=False)

ITEMS = [
    {"id": 1, "name": "alpha"},
    {"id": 2, "name": "beta"},
]


def require_token(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> None:
    expected = os.environ.get("API_TOKEN", "")
    if not expected or creds is None or not secrets.compare_digest(creds.credentials, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized",
            headers={"WWW-Authenticate": "Bearer"},
        )


@app.get("/health")
def health() -> dict[str, str]:
    return {
        "status": "ok",
        "version": os.environ.get("APP_VERSION", "dev"),
        "git_sha": os.environ.get("GIT_SHA", "unknown"),
    }


@app.get("/items", dependencies=[Depends(require_token)])
def list_items() -> list[dict]:
    return ITEMS
