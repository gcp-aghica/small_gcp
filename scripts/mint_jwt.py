"""Выпустить тестовый JWT пользователя, подписанный ключом workspace-auth.

    gcloud secrets versions access latest --secret=workspace-jwt-private-key \
      | uv run python -m scripts.mint_jwt [sub]
"""

import sys
import time

import jwt

from upstreams.workspace_auth import KID


def mint(private_key_pem: str, sub: str = "sandbox-user", ttl: int = 3600) -> str:
    now = int(time.time())
    claims = {"sub": sub, "aud": "authenticated", "role": "authenticated", "iat": now}
    claims["exp"] = now + ttl
    return jwt.encode(claims, private_key_pem, algorithm="RS256", headers={"kid": KID})


if __name__ == "__main__":
    print(mint(sys.stdin.read(), *sys.argv[1:2]))
