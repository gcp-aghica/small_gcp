from collections.abc import Iterator

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from app.auth import jwks_client
from app.settings import get_settings

OBS_TOKEN = "obs-token"
META_TOKEN = "meta-token"


@pytest.fixture(scope="session")
def private_key_pem() -> str:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    return key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode()


@pytest.fixture(autouse=True)
def env(monkeypatch: pytest.MonkeyPatch, private_key_pem: str) -> Iterator[None]:
    """Полный конфиг всех сервисов; отдельные тесты удаляют нужные переменные."""
    values = {
        # calculations-api
        "SUPABASE_URL": "http://upstream",
        "SUPABASE_KEY": "dummy",
        "WORKSPACE_SUPABASE_URL": "http://upstream",
        "OBSERVATION_STORE_API_BASE_URL": "http://upstream",
        "GIT_SHA": "abc1234",
        # Общие с upstream-ами: те же имена и значения по обе стороны, как на DEV.
        "OBSERVATION_STORE_API_BEARER_TOKEN": OBS_TOKEN,
        "METADATA_API_BEARER_TOKEN": META_TOKEN,
        # workspace-auth
        "JWT_PRIVATE_KEY": private_key_pem,
    }
    for k, v in values.items():
        monkeypatch.setenv(k, v)
    get_settings.cache_clear()
    jwks_client.cache_clear()
    yield
    get_settings.cache_clear()
    jwks_client.cache_clear()
