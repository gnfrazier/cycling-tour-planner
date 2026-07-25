"""ctp-service — FastAPI wrapping ctp-core (Architecture §6).

This milestone doesn't implement hosted mode's own endpoints (auth, sync,
Postgres — Leg 4/M6), but `create_app` already gates registration on
`settings.mode` (Architecture §6.1 — endpoints not valid for a mode are not
registered, not merely guarded), so sidecar-only routes never exist at all
when `CTP_MODE=hosted`.
"""

from __future__ import annotations

import asyncio
import dataclasses
import logging
import shutil
from contextlib import asynccontextmanager

import httpx
import osmnx
import rasterio
from fastapi import FastAPI, HTTPException, Response
from fastapi.concurrency import run_in_threadpool
from starlette.datastructures import Headers
from starlette.responses import PlainTextResponse

from ctp_core.elevation import GedtmElevationProvider, enrich_elevation
from ctp_core.export import export_route
from ctp_core.graph import build_graph
from ctp_core.providers import OsmArtHistoryProvider, OsmLodgingProvider
from ctp_core.routing import solve_route
from ctp_core.scoring import THEME_PROFILES, WeightSchedule, score_edges
from ctp_core.trips import propose_day_alternative, solve_trip
from ctp_core.types import BBox, Coord, ExportFormat, Graph, Route, RouteShape, Trip
from ctp_core.weather import OpenMeteoHistoricalWeatherProvider

from .config import Settings
from .schemas import (
    DayAlternativeRequest,
    DayAlternativeResponse,
    DayModel,
    GeocodeResponse,
    HealthResponse,
    RouteGenerateRequest,
    RouteResponse,
    TripGenerateRequest,
    TripResponse,
)

logger = logging.getLogger(__name__)

# Dev-only stand-in for the self-hosted tile pipeline (ROADMAP.md Leg 2 tile
# callout / ARCHITECTURE.md). Flutter only ever talks to ctp-service for
# tiles, never a third party directly — this proxy is what's temporary,
# not that contract. Not for production use (usage-policy-limited upstream).
_TILE_UPSTREAM = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
_TILE_USER_AGENT = "cycle-tour-planner-dev/0.1 (local dev tile proxy)"
_TILE_TIMEOUT = httpx.Timeout(10.0, connect=5.0)

_EXPORT_MEDIA_TYPES = {
    ExportFormat.GPX: "application/gpx+xml",
    ExportFormat.TCX: "application/vnd.garmin.tcx+xml",
    ExportFormat.FIT: "application/vnd.ant.fit",
}

# Generous for this API's small JSON bodies; guards against a public
# listener being handed an oversized declared Content-Length.
_MAX_BODY_BYTES = 1_000_000


class MaxBodySizeMiddleware:
    """Rejects requests whose declared Content-Length exceeds the cap,
    before the body reaches routing/Pydantic."""

    def __init__(self, app, max_bytes: int) -> None:
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] == "http":
            content_length = Headers(scope=scope).get("content-length")
            if content_length is not None and int(content_length) > self.max_bytes:
                response = PlainTextResponse("request body too large", status_code=413)
                await response(scope, receive, send)
                return
        await self.app(scope, receive, send)


def _require_in_bbox(coord: Coord, bbox: BBox, label: str) -> None:
    """Rejects a start/end coordinate outside the served region instead of
    letting `_nearest_node` silently snap it to whatever graph node happens
    to be closest, however far outside the graph's real extent that is."""
    if not (bbox.west <= coord.lon <= bbox.east and bbox.south <= coord.lat <= bbox.north):
        raise HTTPException(
            status_code=400,
            detail=(
                f"{label} point ({coord.lat}, {coord.lon}) is outside the served region "
                f"(west={bbox.west}, south={bbox.south}, east={bbox.east}, north={bbox.north})"
            ),
        )


def _build_base_graph(settings: Settings) -> Graph:
    """Runs once at startup: fetch/cache the graph, then enrich with
    elevation. Deliberately synchronous/blocking — called via a threadpool
    from the async startup task so it doesn't block the event loop."""
    graph = build_graph(settings.bbox, settings.network_type, settings.graph_cache_dir)
    elevation_provider = GedtmElevationProvider([settings.elevation_tile_path])
    return enrich_elevation(graph, elevation_provider)


def create_app(mode: str | None = None, settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings()
    if mode is not None:
        settings.mode = mode

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.settings = settings
        app.state.ready = False
        app.state.graph_base: Graph | None = None
        app.state.routes: dict[str, Route] = {}
        app.state.trips: dict[str, Trip] = {}
        app.state.art_provider = OsmArtHistoryProvider()
        app.state.lodging_provider = OsmLodgingProvider()
        app.state.weather_provider = OpenMeteoHistoricalWeatherProvider()

        async def _load() -> None:
            try:
                app.state.graph_base = await run_in_threadpool(_build_base_graph, settings)
                app.state.ready = True
            except Exception:
                logger.exception("routing engine failed to start")

        load_task = asyncio.create_task(_load())
        yield
        load_task.cancel()

    app = FastAPI(title="Cycle Tour Planner API", lifespan=lifespan)
    app.add_middleware(MaxBodySizeMiddleware, max_bytes=_MAX_BODY_BYTES)
    _register_common_routes(app)
    if settings.mode == "sidecar":
        _register_sidecar_only_routes(app)
    # hosted-only routes (auth/sync/share) are added here at M6 (Architecture
    # §6.2) — endpoints not valid for a mode are not registered at all.
    return app


def _register_common_routes(app: FastAPI) -> None:
    """Endpoints valid in every mode (Architecture §6.2)."""

    @app.get("/health", response_model=HealthResponse)
    def health() -> HealthResponse:
        # Readiness, not liveness (Architecture §6.3) — a sidecar that's up
        # but still loading a large graph is not ready, and the caller must
        # be able to tell the difference.
        return HealthResponse(
            status="ok",
            ready=app.state.ready,
            osmnx_version=osmnx.__version__,
            rasterio_version=rasterio.__version__,
        )

    @app.post("/routes/generate", response_model=RouteResponse)
    async def generate_route(req: RouteGenerateRequest) -> RouteResponse:
        if not app.state.ready:
            raise HTTPException(status_code=503, detail="routing engine still starting up")

        settings: Settings = app.state.settings
        _require_in_bbox(req.start.to_coord(), settings.bbox, "start")
        if req.end is not None:
            _require_in_bbox(req.end.to_coord(), settings.bbox, "destination")

        schedule = WeightSchedule(THEME_PROFILES[req.theme])

        def _solve() -> Route:
            graph = app.state.graph_base.copy()
            graph = score_edges(graph, schedule, bbox=settings.bbox, providers=[app.state.art_provider])
            return solve_route(
                graph,
                start=req.start.to_coord(),
                end=req.end.to_coord() if req.end else None,
                shape=req.shape,
                theme=req.theme,
                cpus=2,
                target_distance_km=req.target_distance_km,
            )

        try:
            route = await run_in_threadpool(_solve)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        app.state.routes[route.id] = route
        return RouteResponse.from_route(route)

    @app.post("/routes/{route_id}/export")
    async def export_route_endpoint(route_id: str, fmt: ExportFormat) -> Response:
        route = app.state.routes.get(route_id)
        if route is None:
            raise HTTPException(status_code=404, detail="route not found")

        data = await run_in_threadpool(export_route, route, fmt)
        return Response(
            content=data,
            media_type=_EXPORT_MEDIA_TYPES[fmt],
            headers={"Content-Disposition": f'attachment; filename="route.{fmt.value}"'},
        )

    @app.post("/trips/generate", response_model=TripResponse)
    async def generate_trip(req: TripGenerateRequest) -> TripResponse:
        if not app.state.ready:
            raise HTTPException(status_code=503, detail="routing engine still starting up")

        settings: Settings = app.state.settings
        for index, waypoint in enumerate(req.waypoints):
            _require_in_bbox(waypoint.coord.to_coord(), settings.bbox, f"waypoint {index}")

        base_profile = THEME_PROFILES[req.theme]
        tour_profile = dataclasses.replace(
            base_profile, elevation_gain=req.elevation_gain, surface_preference=req.surface_preference
        )
        overrides = [override.to_weight_override(base_profile) for override in req.overrides]
        day_split = req.day_split.to_day_split_config() if req.day_split else None

        def _solve() -> Trip:
            graph = app.state.graph_base.copy()
            return solve_trip(
                graph,
                waypoints=[wp.to_waypoint() for wp in req.waypoints],
                theme=req.theme,
                tour_profile=tour_profile,
                overrides=overrides,
                rider_band=req.rider_band,
                lodging_provider=app.state.lodging_provider,
                weather_provider=app.state.weather_provider,
                bbox=settings.bbox,
                start_date=req.start_date,
                day_split=day_split,
                providers=[app.state.art_provider],
            )

        try:
            trip = await run_in_threadpool(_solve)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        app.state.trips[trip.id] = trip
        return TripResponse.from_trip(trip)

    @app.post("/trips/{trip_id}/days/{day_index}/reroute", response_model=DayAlternativeResponse)
    async def reroute_day(trip_id: str, day_index: int, req: DayAlternativeRequest) -> DayAlternativeResponse:
        """FR42 — proposes an alternative for one day under a different
        weighting, alongside the current day, without touching the stored
        trip. The client draws both (ghost vs. bold); nothing is committed
        until "make active" is called separately."""
        trip = app.state.trips.get(trip_id)
        if trip is None:
            raise HTTPException(status_code=404, detail="trip not found")
        if not 0 <= day_index < len(trip.days):
            raise HTTPException(status_code=404, detail=f"trip has no day {day_index}")

        settings: Settings = app.state.settings
        base_profile = THEME_PROFILES[trip.theme]
        alt_profile = dataclasses.replace(
            base_profile, elevation_gain=req.elevation_gain, surface_preference=req.surface_preference
        )

        def _propose():
            graph = app.state.graph_base.copy()
            return propose_day_alternative(
                graph,
                trip,
                day_index,
                alt_profile,
                lodging_provider=app.state.lodging_provider,
                weather_provider=app.state.weather_provider,
                bbox=settings.bbox,
                start_date=trip.start_date,
                providers=[app.state.art_provider],
                segment_start_km=req.segment_start_km,
                segment_end_km=req.segment_end_km,
            )

        try:
            alternative = await run_in_threadpool(_propose)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        return DayAlternativeResponse(
            current=DayModel.from_day(trip.days[day_index]),
            alternative=DayModel.from_day(alternative),
        )

    @app.post("/trips/{trip_id}/days/{day_index}/apply-alternative", response_model=TripResponse)
    async def apply_day_alternative(trip_id: str, day_index: int, req: DayAlternativeRequest) -> TripResponse:
        """FR42 "make active" — recomputes the same alternative and swaps it
        into the stored trip in place. Per the PRD's own wording
        ("recomputes the day's totals," singular), only that day's totals
        change — later days keep their existing boundaries, since the
        alternative shares the same start/end waypoints as the day it
        replaces."""
        trip = app.state.trips.get(trip_id)
        if trip is None:
            raise HTTPException(status_code=404, detail="trip not found")
        if not 0 <= day_index < len(trip.days):
            raise HTTPException(status_code=404, detail=f"trip has no day {day_index}")

        settings: Settings = app.state.settings
        base_profile = THEME_PROFILES[trip.theme]
        alt_profile = dataclasses.replace(
            base_profile, elevation_gain=req.elevation_gain, surface_preference=req.surface_preference
        )

        def _apply():
            graph = app.state.graph_base.copy()
            return propose_day_alternative(
                graph,
                trip,
                day_index,
                alt_profile,
                lodging_provider=app.state.lodging_provider,
                weather_provider=app.state.weather_provider,
                bbox=settings.bbox,
                start_date=trip.start_date,
                providers=[app.state.art_provider],
                segment_start_km=req.segment_start_km,
                segment_end_km=req.segment_end_km,
            )

        try:
            alternative = await run_in_threadpool(_apply)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        trip.days[day_index] = alternative
        trip.total_distance_m = sum(day.distance_m for day in trip.days)
        trip.total_elevation_gain_m = sum(day.elevation_gain_m for day in trip.days)
        return TripResponse.from_trip(trip)

    @app.post("/trips/{trip_id}/days/{day_index}/export")
    async def export_day_endpoint(trip_id: str, day_index: int, fmt: ExportFormat) -> Response:
        trip = app.state.trips.get(trip_id)
        if trip is None:
            raise HTTPException(status_code=404, detail="trip not found")
        if not 0 <= day_index < len(trip.days):
            raise HTTPException(status_code=404, detail=f"trip has no day {day_index}")

        day = trip.days[day_index]
        day_route = Route(
            id=f"{trip_id}-day{day_index}",
            theme=trip.theme,
            shape=RouteShape.POINT_TO_POINT,
            coords=day.coords,
            distance_m=day.distance_m,
            elevation_gain_m=day.elevation_gain_m,
        )
        data = await run_in_threadpool(export_route, day_route, fmt)
        return Response(
            content=data,
            media_type=_EXPORT_MEDIA_TYPES[fmt],
            headers={"Content-Disposition": f'attachment; filename="day{day_index + 1}.{fmt.value}"'},
        )

    @app.get("/geocode", response_model=GeocodeResponse)
    async def geocode(q: str) -> GeocodeResponse:
        try:
            lat, lon = await run_in_threadpool(osmnx.geocoder.geocode, q)
        except Exception as exc:
            raise HTTPException(status_code=404, detail=f"could not geocode {q!r}") from exc
        return GeocodeResponse(lat=lat, lon=lon, display_name=q)


def _register_sidecar_only_routes(app: FastAPI) -> None:
    """Endpoints valid only in sidecar mode (Architecture §6.2) — not
    registered at all in hosted mode, not merely guarded (§6.1)."""

    @app.post("/admin/clear-cache")
    async def clear_cache() -> dict:
        """FR39 (desktop half) — prune downloaded region data. Deletes the
        on-disk OSMnx graph cache; the in-memory graph already loaded keeps
        serving until the process restarts, at which point the region is
        re-fetched fresh. Not a hot in-place reload — out of scope here."""
        graph_dir = app.state.settings.graph_cache_dir
        cleared = graph_dir.exists()
        if cleared:
            await run_in_threadpool(shutil.rmtree, graph_dir, True)
        return {"cleared": cleared}

    @app.get("/tiles/{z}/{x}/{y}")
    async def tile(z: int, x: int, y: int) -> Response:
        if not (0 <= z <= 19 and 0 <= x < 2**z and 0 <= y < 2**z):
            raise HTTPException(status_code=400, detail="tile coordinates out of range")

        url = _TILE_UPSTREAM.format(z=z, x=x, y=y)
        async with httpx.AsyncClient(timeout=_TILE_TIMEOUT) as client:
            resp = await client.get(url, headers={"User-Agent": _TILE_USER_AGENT})
        if resp.status_code != 200:
            raise HTTPException(status_code=resp.status_code, detail="tile upstream error")
        return Response(content=resp.content, media_type="image/png")
