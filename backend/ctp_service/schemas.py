"""Pydantic request/response models for ctp-service."""

from __future__ import annotations

from pydantic import BaseModel, Field

from ctp_core.types import Coord, ExportFormat, Route, RouteShape, Theme


class CoordModel(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)

    def to_coord(self) -> Coord:
        return Coord(lat=self.lat, lon=self.lon)


class RouteGenerateRequest(BaseModel):
    start: CoordModel
    theme: Theme
    shape: RouteShape
    end: CoordModel | None = None
    # Upper bound keeps _node_near_distance's Dijkstra search bounded; matches
    # the client's FR47 slider ceiling (10km floor, 300km/180mi ceiling).
    target_distance_km: float | None = Field(default=None, gt=0, le=300)


class RouteResponse(BaseModel):
    id: str
    theme: Theme
    shape: RouteShape
    coords: list[CoordModel]
    distance_m: float
    elevation_gain_m: float

    @classmethod
    def from_route(cls, route: Route) -> RouteResponse:
        return cls(
            id=route.id,
            theme=route.theme,
            shape=route.shape,
            coords=[CoordModel(lat=c.lat, lon=c.lon) for c in route.coords],
            distance_m=route.distance_m,
            elevation_gain_m=route.elevation_gain_m,
        )


class GeocodeResponse(BaseModel):
    lat: float
    lon: float
    display_name: str


class HealthResponse(BaseModel):
    status: str
    ready: bool
    osmnx_version: str
    rasterio_version: str


# Re-exported so ctp_service call sites don't need to import ctp_core directly
# for the export format path parameter.
__all__ = [
    "CoordModel",
    "ExportFormat",
    "GeocodeResponse",
    "HealthResponse",
    "RouteGenerateRequest",
    "RouteResponse",
]
