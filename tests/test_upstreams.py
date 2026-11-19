from fastapi.testclient import TestClient

from tests.conftest import META_TOKEN, OBS_TOKEN
from upstreams.metadata_api import app as metadata_app
from upstreams.observation_store_api import app as observation_app
from upstreams.workspace_auth import app as workspace_app

observation = TestClient(observation_app)
metadata = TestClient(metadata_app)
workspace = TestClient(workspace_app)


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_health_everywhere() -> None:
    for client in (observation, metadata, workspace):
        assert client.get("/health").json() == {"status": "ok", "git_sha": "abc1234"}


def test_jwks_has_public_key_only() -> None:
    keys = workspace.get("/auth/v1/.well-known/jwks.json").json()["keys"]
    assert len(keys) == 1
    assert keys[0]["kid"] == "sandbox-1"
    assert keys[0]["kty"] == "RSA"
    assert "d" not in keys[0]  # приватная часть не утекает


def test_series_requires_observation_token() -> None:
    params = {"site_id": "s1"}
    assert observation.get("/v1/series", params=params).status_code == 401
    assert (
        observation.get("/v1/series", params=params, headers=bearer(META_TOKEN)).status_code == 401
    )
    resp = observation.get("/v1/series", params=params, headers=bearer(OBS_TOKEN))
    assert resp.status_code == 200
    assert len(resp.json()["points"]) == 3


def test_metadata_requires_metadata_token() -> None:
    params = {"country": "CH"}
    assert metadata.get("/v1/ppp", params=params, headers=bearer(META_TOKEN)).status_code == 200
    assert metadata.get("/v1/ppp", params=params, headers=bearer(OBS_TOKEN)).status_code == 401
    assert metadata.get("/v1/ppp", params=params).status_code == 401
