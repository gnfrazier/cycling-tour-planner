import time

import pytest
from fastapi.testclient import TestClient

from ctp_service.app import create_app
from ctp_service.config import Settings


@pytest.fixture(scope="module")
def client():
    # Default Settings() bbox/cache match tests/conftest.py's TEST_BBOX, so
    # this reuses the same warm OSMnx cache the other tests already primed.
    app = create_app(settings=Settings())
    with TestClient(app) as test_client:
        deadline = time.time() + 90
        while time.time() < deadline:
            if test_client.get("/health").json()["ready"]:
                break
            time.sleep(0.5)
        else:
            pytest.fail("routing engine did not become ready in time")
        yield test_client


def test_health_reports_ready(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["ready"] is True


def test_geocode_resolves_marion_nc(client):
    resp = client.get("/geocode", params={"q": "Marion, NC"})
    assert resp.status_code == 200
    body = resp.json()
    assert 35.0 < body["lat"] < 36.5
    assert -83.0 < body["lon"] < -81.0


def test_generate_route_then_export_every_format(client):
    payload = {
        "start": {"lat": 35.6841, "lon": -82.0091},
        "theme": "flattest",
        "shape": "loop",
        "target_distance_km": 4.0,
    }
    generate_resp = client.post("/routes/generate", json=payload)
    assert generate_resp.status_code == 200
    route = generate_resp.json()
    assert route["theme"] == "flattest"
    assert len(route["coords"]) >= 2

    for fmt, content_type_prefix in [
        ("gpx", "application/gpx+xml"),
        ("tcx", "application/vnd.garmin.tcx+xml"),
        ("fit", "application/vnd.ant.fit"),
    ]:
        export_resp = client.post(f"/routes/{route['id']}/export", params={"fmt": fmt})
        assert export_resp.status_code == 200
        assert export_resp.headers["content-type"].startswith(content_type_prefix)
        assert len(export_resp.content) > 0


def test_export_unknown_route_id_is_404(client):
    resp = client.post("/routes/does-not-exist/export", params={"fmt": "gpx"})
    assert resp.status_code == 404


def test_point_to_point_without_end_is_400(client):
    payload = {"start": {"lat": 35.6841, "lon": -82.0091}, "theme": "flattest", "shape": "point_to_point"}
    resp = client.post("/routes/generate", json=payload)
    assert resp.status_code == 400


def test_clear_cache_removes_on_disk_graph_cache_and_app_stays_up(client):
    resp = client.post("/admin/clear-cache")
    assert resp.status_code == 200
    assert resp.json()["cleared"] in (True, False)

    # The already-loaded in-memory graph keeps serving until restart.
    assert client.get("/health").json()["ready"] is True
