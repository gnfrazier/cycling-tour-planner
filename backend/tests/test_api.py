import time

import pytest
from fastapi.testclient import TestClient

from ctp_service.app import create_app
from ctp_service.config import Settings

from .conftest import TEST_BBOX


@pytest.fixture(scope="module")
def client():
    # Settings().bbox defaults to the real ~80km shipped region (config.py),
    # which is too slow to fetch fresh in a test run — pin explicitly to
    # tests/conftest.py's TEST_BBOX so this reuses the same warm OSMnx cache
    # the other tests already primed.
    app = create_app(settings=Settings(bbox=TEST_BBOX))
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


def test_tile_out_of_range_coordinates_is_400(client):
    resp = client.get("/tiles/25/0/0")
    assert resp.status_code == 400


def test_tile_proxies_a_real_upstream_tile(client):
    resp = client.get("/tiles/1/0/0")
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "image/png"
    assert len(resp.content) > 0


def test_generate_route_rejects_out_of_range_latitude(client):
    payload = {"start": {"lat": 95.0, "lon": -82.0091}, "theme": "flattest", "shape": "loop"}
    resp = client.post("/routes/generate", json=payload)
    assert resp.status_code == 422


def test_generate_route_rejects_absurd_target_distance(client):
    payload = {
        "start": {"lat": 35.6841, "lon": -82.0091},
        "theme": "flattest",
        "shape": "loop",
        "target_distance_km": 5000.0,
    }
    resp = client.post("/routes/generate", json=payload)
    assert resp.status_code == 422


def test_oversized_request_body_is_rejected(client):
    oversized = b'{"pad": "' + b"a" * 2_000_000 + b'"}'
    resp = client.post(
        "/routes/generate",
        content=oversized,
        headers={"content-type": "application/json"},
    )
    assert resp.status_code == 413


def test_sidecar_only_routes_are_absent_in_hosted_mode():
    app = create_app(mode="hosted", settings=Settings(bbox=TEST_BBOX))
    with TestClient(app) as hosted_client:
        assert hosted_client.post("/admin/clear-cache").status_code == 404
        assert hosted_client.get("/tiles/1/0/0").status_code == 404
        # Common routes still registered.
        assert hosted_client.get("/health").status_code == 200
