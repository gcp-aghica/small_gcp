import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


@pytest.fixture
def token(monkeypatch: pytest.MonkeyPatch) -> str:
    value = "test-token"
    monkeypatch.setenv("API_TOKEN", value)
    return value


def test_health_ok(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GIT_SHA", "abc1234")
    monkeypatch.setenv("APP_VERSION", "1.2.3")
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "version": "1.2.3", "git_sha": "abc1234"}


def test_health_defaults(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("GIT_SHA", raising=False)
    monkeypatch.delenv("APP_VERSION", raising=False)
    assert client.get("/health").json()["git_sha"] == "unknown"


def test_items_without_token_is_401(token: str) -> None:
    resp = client.get("/items")
    assert resp.status_code == 401
    assert resp.headers["www-authenticate"] == "Bearer"


def test_items_wrong_token_is_401(token: str) -> None:
    resp = client.get("/items", headers={"Authorization": "Bearer nope"})
    assert resp.status_code == 401


def test_items_with_token(token: str) -> None:
    resp = client.get("/items", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    assert len(resp.json()) == 2


def test_items_401_when_server_token_not_configured(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("API_TOKEN", raising=False)
    resp = client.get("/items", headers={"Authorization": "Bearer "})
    assert resp.status_code == 401
