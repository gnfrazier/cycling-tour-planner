"""ctp-service — FastAPI wrapping ctp-core (Architecture §6).

Sidecar mode only: this milestone doesn't implement hosted mode (auth,
sync, Postgres — Leg 4/M6), so `create_app` registers only the routing
endpoints valid in every mode (Architecture §6.1 — endpoints not valid for
a mode are not registered, not merely guarded).
"""

from __future__ import annotations

import asyncio
import logging
import shutil
from contextlib import asynccontextmanager

import httpx
import osmnx
import rasterio
from fastapi import FastAPI, HTTPException, Response
from fastapi.concurrency import run_in_threadpool

from ctp_core.elevation import GedtmElevationProvider, enrich_elevation
from ctp_core.export import export_route
from ctp_core.graph import build_graph
from ctp_core.providers import OsmArtHistoryProvider
from ctp_core.routing import solve_route
from ctp_core.scoring import THEME_PROFILES, WeightSchedule, score_edges
from ctp_core.types import ExportFormat, Graph, Route

from .config import Settings
from .schemas import GeocodeResponse, HealthResponse, RouteGenerateRequest, RouteResponse

logger = logging.getLogger(__name__)

# Dev-only stand-in for the self-hosted tile pipeline (ROADMAP.md Leg 2 tile
# callout / ARCHITECTURE.md). Flutter only ever talks to ctp-service for
# tiles, never a third party directly — this proxy is what's temporary,
# not that contract. Not for production use (usage-policy-limited upstream).
_TILE_UPSTREAM = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
_TILE_USER_AGENT = "cycle-tour-planner-dev/0.1 (local dev tile proxy)"

_EXPORT_MEDIA_TYPES = {
    ExportFormat.GPX: "application/gpx+xml",
    ExportFormat.TCX: "application/vnd.garmin.tcx+xml",
    ExportFormat.FIT: "application/vnd.ant.fit",
}


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
        app.state.art_provider = OsmArtHistoryProvider()

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
    _register_routing_routes(app)
    return app


def _register_routing_routes(app: FastAPI) -> None:
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

    @app.post("/routes/generate", response_model=RouteResponse)
    async def generate_route(req: RouteGenerateRequest) -> RouteResponse:
        if not app.state.ready:
            raise HTTPException(status_code=503, detail="routing engine still starting up")

        settings: Settings = app.state.settings
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

    @app.get("/geocode", response_model=GeocodeResponse)
    async def geocode(q: str) -> GeocodeResponse:
        try:
            lat, lon = await run_in_threadpool(osmnx.geocoder.geocode, q)
        except Exception as exc:
            raise HTTPException(status_code=404, detail=f"could not geocode {q!r}") from exc
        return GeocodeResponse(lat=lat, lon=lon, display_name=q)

    @app.get("/tiles/{z}/{x}/{y}")
    async def tile(z: int, x: int, y: int) -> Response:
        url = _TILE_UPSTREAM.format(z=z, x=x, y=y)
        async with httpx.AsyncClient() as client:
            resp = await client.get(url, headers={"User-Agent": _TILE_USER_AGENT})
        if resp.status_code != 200:
            raise HTTPException(status_code=resp.status_code, detail="tile upstream error")
        return Response(content=resp.content, media_type="image/png")
