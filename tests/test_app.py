from collections.abc import Iterator

import httpx
import jwt
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.upstream import observation_client
from scripts.mint_jwt import mint
from tests.conftest import OBS_TOKEN
from upstreams.observation_store_api import app as observation_app
from upstreams.workspace_auth import app as workspace_app

WORKSPACE = TestClient(workspace_app)


@pytest.fixture(autouse=True)
def wire_upstreams(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    """JWKS отдаёт заглушка workspace-auth, только без сети."""
    monkeypatch.setattr(
        jwt.PyJWKClient,
        "fetch_data",
        lambda self: WORKSPACE.get("/auth/v1/.well-known/jwks.json").json(),
    )
    yield
    app.dependency_overrides.clear()


def use_upstream_token(token: str) -> None:
    def override() -> Iterator[httpx.Client]:
        with TestClient(observation_app, headers={"Authorization": f"Bearer {token}"}) as c:
            yield c

    app.dependency_overrides[observation_client] = override


@pytest.fixture
def user_token(private_key_pem: str) -> str:
    return mint(private_key_pem, sub="user-1")


def test_health() -> None:
    with TestClient(app) as client:
        assert client.get("/health").json() == {"status": "ok", "git_sha": "abc1234"}


@pytest.mark.parametrize("name", ["SUPABASE_URL", "SUPABASE_KEY", "WORKSPACE_SUPABASE_URL"])
def test_startup_fails_without_required_var(monkeypatch: pytest.MonkeyPatch, name: str) -> None:
    monkeypatch.delenv(name)
    with pytest.raises(Exception, match=name.lower()), TestClient(app):
        pass


def test_startup_ok_without_upstream_vars(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in ["OBSERVATION_STORE_API_BASE_URL", "OBSERVATION_STORE_API_BEARER_TOKEN"]:
        monkeypatch.delenv(name)
    with TestClient(app) as client:
        assert client.get("/health").status_code == 200


def test_risk_without_jwt_is_401() -> None:
    with TestClient(app) as client:
        resp = client.get("/risk/site", params={"site_id": "s1"})
    assert resp.status_code == 401
    assert resp.headers["www-authenticate"] == "Bearer"


def test_risk_with_foreign_jwt_is_401() -> None:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    other = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = other.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode()
    with TestClient(app) as client:
        resp = client.get(
            "/risk/site",
            params={"site_id": "s1"},
            headers={"Authorization": f"Bearer {mint(pem)}"},
        )
    assert resp.status_code == 401


def test_risk_ok(user_token: str) -> None:
    use_upstream_token(OBS_TOKEN)
    with TestClient(app) as client:
        resp = client.get(
            "/risk/site",
            params={"site_id": "s1"},
            headers={"Authorization": f"Bearer {user_token}"},
        )
    assert resp.status_code == 200
    assert resp.json() == {
        "site_id": "s1",
        "user": "user-1",
        "points": 3,
        "max_temperature": 31.0,
    }


def test_wrong_shared_token_is_502_not_401(user_token: str) -> None:
    """Сценарий 3: рассинхрон общего observation-api-token — ошибка upstream, не 401."""
    use_upstream_token("stale-token")
    with TestClient(app) as client:
        resp = client.get(
            "/risk/site",
            params={"site_id": "s1"},
            headers={"Authorization": f"Bearer {user_token}"},
        )
    assert resp.status_code == 502
    assert resp.json()["detail"] == "observation-store-api: HTTP 401"


def test_unreachable_upstream_is_502(monkeypatch: pytest.MonkeyPatch, user_token: str) -> None:
    monkeypatch.setenv("OBSERVATION_STORE_API_BASE_URL", "http://127.0.0.1:9")
    with TestClient(app) as client:
        resp = client.get(
            "/risk/site",
            params={"site_id": "s1"},
            headers={"Authorization": f"Bearer {user_token}"},
        )
    assert resp.status_code == 502
