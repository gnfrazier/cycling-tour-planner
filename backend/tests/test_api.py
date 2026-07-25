import asyncio
import time

import pytest
from fastapi.testclient import TestClient

from ctp_service.app import MaxBodySizeMiddleware, _store_bounded, create_app
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
    assert route["surface_breakdown_m"]
    assert route["traffic_breakdown_m"]

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


def test_generate_route_rejects_start_outside_bbox(client):
    payload = {"start": {"lat": 36.5, "lon": -83.0}, "theme": "flattest", "shape": "loop", "target_distance_km": 4.0}
    resp = client.post("/routes/generate", json=payload)
    assert resp.status_code == 400
    assert "outside" in resp.json()["detail"]


def test_generate_route_rejects_destination_outside_bbox(client):
    payload = {
        "start": {"lat": 35.6841, "lon": -82.0091},
        "end": {"lat": 36.5, "lon": -83.0},
        "theme": "flattest",
        "shape": "point_to_point",
    }
    resp = client.post("/routes/generate", json=payload)
    assert resp.status_code == 400
    assert "outside" in resp.json()["detail"]


def test_oversized_request_body_is_rejected(client):
    oversized = b'{"pad": "' + b"a" * 2_000_000 + b'"}'
    resp = client.post(
        "/routes/generate",
        content=oversized,
        headers={"content-type": "application/json"},
    )
    assert resp.status_code == 413


def test_body_size_cap_enforced_even_without_a_content_length_header():
    """A declared Content-Length is what the header-only check inspects —
    but chunked transfer-encoding (or a client simply omitting/understating
    the header) carries no such header at all, and must still be caught
    against the real bytes received as they stream in."""

    async def _dummy_app(scope, receive, send):
        while True:
            message = await receive()
            if not message.get("more_body", False):
                break
        await send({"type": "http.response.start", "status": 200, "headers": []})
        await send({"type": "http.response.body", "body": b"ok"})

    middleware = MaxBodySizeMiddleware(_dummy_app, max_bytes=10)
    scope = {"type": "http", "headers": []}  # no content-length header at all
    chunks = [b"a" * 6, b"b" * 6]  # 12 bytes total, over the cap, arriving in pieces

    async def receive():
        chunk = chunks.pop(0) if chunks else b""
        return {"type": "http.request", "body": chunk, "more_body": bool(chunks)}

    sent = []

    async def send(message):
        sent.append(message)

    asyncio.run(middleware(scope, receive, send))

    assert sent[0]["status"] == 413


def test_store_bounded_evicts_oldest_entry_past_the_cap():
    store: dict[str, int] = {}
    for i in range(5):
        _store_bounded(store, f"key{i}", i, max_size=3)

    assert len(store) == 3
    # The two oldest insertions (key0, key1) are gone; the three most recent remain.
    assert list(store.keys()) == ["key2", "key3", "key4"]


def test_sidecar_only_routes_are_absent_in_hosted_mode():
    app = create_app(mode="hosted", settings=Settings(bbox=TEST_BBOX))
    with TestClient(app) as hosted_client:
        assert hosted_client.post("/admin/clear-cache").status_code == 404
        assert hosted_client.get("/tiles/1/0/0").status_code == 404
        # Common routes still registered.
        assert hosted_client.get("/health").status_code == 200


# FR10-FR15/FR42/FR46 -- multi-day trip endpoints (Leg 3 / M5)

_TRIP_WAYPOINTS = [
    {"coord": {"lat": 35.6841, "lon": -82.0091}},
    {"coord": {"lat": 35.695, "lon": -82.010}},
]


def _trip_payload(**overrides):
    payload = {
        "waypoints": _TRIP_WAYPOINTS,
        "theme": "flattest",
        "rider_band": "solo",
        "start_date": "2026-06-01",
        "day_split": {"min_daily_km": 0.1, "max_daily_km": 1.0},
    }
    payload.update(overrides)
    return payload


def test_generate_trip_then_reroute_apply_and_export_every_day(client):
    generate_resp = client.post("/trips/generate", json=_trip_payload())
    assert generate_resp.status_code == 200
    trip = generate_resp.json()
    assert trip["theme"] == "flattest"
    assert len(trip["days"]) > 1  # the tight day_split cap should force a split

    reroute_resp = client.post(
        f"/trips/{trip['id']}/days/0/reroute",
        json={"surface_preference": -1.0},
    )
    assert reroute_resp.status_code == 200
    comparison = reroute_resp.json()
    assert "current" in comparison and "alternative" in comparison
    assert comparison["current"]["index"] == 0

    apply_resp = client.post(
        f"/trips/{trip['id']}/days/0/apply-alternative",
        json={"surface_preference": -1.0},
    )
    assert apply_resp.status_code == 200
    updated_trip = apply_resp.json()
    assert len(updated_trip["days"]) == len(trip["days"])  # later days untouched

    for fmt, content_type_prefix in [
        ("gpx", "application/gpx+xml"),
        ("tcx", "application/vnd.garmin.tcx+xml"),
        ("fit", "application/vnd.ant.fit"),
    ]:
        export_resp = client.post(f"/trips/{trip['id']}/days/0/export", params={"fmt": fmt})
        assert export_resp.status_code == 200
        assert export_resp.headers["content-type"].startswith(content_type_prefix)
        assert len(export_resp.content) > 0


def test_generate_trip_rejects_a_single_waypoint(client):
    resp = client.post("/trips/generate", json=_trip_payload(waypoints=_TRIP_WAYPOINTS[:1]))
    assert resp.status_code == 422


def test_generate_trip_rejects_waypoint_outside_bbox(client):
    payload = _trip_payload(waypoints=[_TRIP_WAYPOINTS[0], {"coord": {"lat": 36.5, "lon": -83.0}}])
    resp = client.post("/trips/generate", json=payload)
    assert resp.status_code == 400
    assert "outside" in resp.json()["detail"]


def test_generate_trip_rejects_out_of_range_override_day_index(client):
    payload = _trip_payload(overrides=[{"day_index": 99, "elevation_gain": 1.0}])
    resp = client.post("/trips/generate", json=payload)
    assert resp.status_code == 400


def test_reroute_unknown_trip_is_404(client):
    resp = client.post("/trips/does-not-exist/days/0/reroute", json={})
    assert resp.status_code == 404


def test_reroute_unknown_day_index_is_404(client):
    generate_resp = client.post("/trips/generate", json=_trip_payload())
    trip_id = generate_resp.json()["id"]
    resp = client.post(f"/trips/{trip_id}/days/99/reroute", json={})
    assert resp.status_code == 404


def test_export_day_unknown_trip_is_404(client):
    resp = client.post("/trips/does-not-exist/days/0/export", params={"fmt": "gpx"})
    assert resp.status_code == 404
