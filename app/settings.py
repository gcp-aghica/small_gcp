"""Конфиг сервиса. Имена переменных совпадают с calculations-api.

Обязательные поля проверяются при старте: без них процесс падает, ревизия Cloud Run
не проходит startup probe, и трафик остаётся на старой ревизии. Upstream-переменные
(Observation, Metadata, HMAC) в calculations-api при старте не проверяются, здесь так же.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(extra="ignore")

    # Обязательные: проверяются при старте.
    supabase_url: str
    supabase_key: str
    workspace_supabase_url: str

    # Необязательные при старте, но нужны эндпоинтам.
    cors_origins: str = ""
    observation_store_api_base_url: str = ""
    observation_store_api_bearer_token: str = ""
    metadata_api_base_url: str = ""
    metadata_api_bearer_token: str = ""
    gcs_hmac_key_id: str = ""
    gcs_hmac_secret: str = ""

    # Вшит в образ (--build-arg GIT_SHA).
    git_sha: str = "unknown"

    @property
    def jwks_url(self) -> str:
        return f"{self.workspace_supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json"


def split_origins(value: str) -> list[str]:
    """CORS_ORIGINS через запятую; пусто = CORS закрыт."""
    return [o.strip() for o in value.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]  # поля приходят из env
