"""Pydantic request/response models for ctp-service."""

from __future__ import annotations

import dataclasses
import datetime

from pydantic import BaseModel, Field

from ctp_core.types import (
    Coord,
    Day,
    DaySplitConfig,
    ExportFormat,
    LodgingOption,
    RiderBand,
    Route,
    RouteShape,
    Theme,
    Trip,
    Waypoint,
    WeatherSummary,
    WeightOverride,
    WeightProfile,
)


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


class WaypointModel(BaseModel):
    coord: CoordModel
    label: str | None = None

    def to_waypoint(self) -> Waypoint:
        return Waypoint(coord=self.coord.to_coord(), label=self.label)

    @classmethod
    def from_waypoint(cls, waypoint: Waypoint) -> WaypointModel:
        return cls(coord=CoordModel(lat=waypoint.coord.lat, lon=waypoint.coord.lon), label=waypoint.label)


class DaySplitConfigModel(BaseModel):
    # FR11 — bounds are generous but finite: keeps the greedy day-split walk
    # (and the FR13 re-solve pass) bounded, matching the target-distance
    # bound already used for single-route generation.
    min_daily_km: float = Field(gt=0, le=500)
    max_daily_km: float = Field(gt=0, le=500)
    max_daily_elevation_m: float | None = Field(default=None, gt=0)

    def to_day_split_config(self) -> DaySplitConfig:
        return DaySplitConfig(
            min_daily_km=self.min_daily_km,
            max_daily_km=self.max_daily_km,
            max_daily_elevation_m=self.max_daily_elevation_m,
        )


class WeightOverrideModel(BaseModel):
    """FR13 — a day- or partial-day-segment-scoped weighting override. Only
    elevation-gain and surface-preference are exposed on a sliding scale
    (PRD's own stated scope for FR13); everything else in the profile
    inherits from the trip's theme, same as `elevation_gain`/
    `surface_preference` on `TripGenerateRequest`."""

    day_index: int = Field(ge=0)
    elevation_gain: float = Field(default=0.0, ge=-1.0, le=1.0)
    surface_preference: float = Field(default=0.0, ge=-1.0, le=1.0)
    segment_start_km: float | None = Field(default=None, ge=0)
    segment_end_km: float | None = Field(default=None, gt=0)

    def to_weight_override(self, base_profile: WeightProfile) -> WeightOverride:
        profile = dataclasses.replace(
            base_profile, elevation_gain=self.elevation_gain, surface_preference=self.surface_preference
        )
        return WeightOverride(
            day_index=self.day_index,
            profile=profile,
            segment_start_km=self.segment_start_km,
            segment_end_km=self.segment_end_km,
        )


class TripGenerateRequest(BaseModel):
    waypoints: list[WaypointModel] = Field(min_length=2)
    theme: Theme
    elevation_gain: float = Field(default=0.0, ge=-1.0, le=1.0)
    surface_preference: float = Field(default=0.0, ge=-1.0, le=1.0)
    overrides: list[WeightOverrideModel] = Field(default_factory=list)
    day_split: DaySplitConfigModel | None = None
    rider_band: RiderBand = RiderBand.SOLO
    start_date: datetime.date


class DayAlternativeRequest(BaseModel):
    """FR42 — the weighting to try for one day/segment. Shared by the
    "propose" and "make active" endpoints so a proposal is always recomputed
    fresh from an explicit request, rather than cached server-side pending
    state the client has to track."""

    elevation_gain: float = Field(default=0.0, ge=-1.0, le=1.0)
    surface_preference: float = Field(default=0.0, ge=-1.0, le=1.0)
    segment_start_km: float | None = Field(default=None, ge=0)
    segment_end_km: float | None = Field(default=None, gt=0)


class LodgingOptionModel(BaseModel):
    name: str
    kind: str
    coord: CoordModel
    distance_from_day_end_m: float

    @classmethod
    def from_lodging_option(cls, option: LodgingOption) -> LodgingOptionModel:
        return cls(
            name=option.name,
            kind=option.kind,
            coord=CoordModel(lat=option.coord.lat, lon=option.coord.lon),
            distance_from_day_end_m=option.distance_from_day_end_m,
        )


class WeatherSummaryModel(BaseModel):
    month: int
    day: int
    temp_min_c: float
    temp_max_c: float
    apparent_temp_c: float
    wind_speed_kph: float
    wind_direction_deg: float
    precip_probability_pct: float
    precip_timing: str | None
    years_averaged: int
    pm2_5: float | None
    pm10: float | None
    o3: float | None
    no2: float | None
    uv_index: float | None
    pollen: dict[str, float] | None

    @classmethod
    def from_weather_summary(cls, summary: WeatherSummary) -> WeatherSummaryModel:
        return cls(**dataclasses.asdict(summary))


class DayModel(BaseModel):
    index: int
    coords: list[CoordModel]
    distance_m: float
    elevation_gain_m: float
    surface_breakdown_m: dict[str, float]
    lodging_options: list[LodgingOptionModel]
    weather: WeatherSummaryModel | None
    regroup_cautions: list[str]

    @classmethod
    def from_day(cls, day: Day) -> DayModel:
        return cls(
            index=day.index,
            coords=[CoordModel(lat=c.lat, lon=c.lon) for c in day.coords],
            distance_m=day.distance_m,
            elevation_gain_m=day.elevation_gain_m,
            surface_breakdown_m=day.surface_breakdown_m,
            lodging_options=[LodgingOptionModel.from_lodging_option(o) for o in day.lodging_options],
            weather=WeatherSummaryModel.from_weather_summary(day.weather) if day.weather else None,
            regroup_cautions=day.regroup_cautions,
        )


class TripResponse(BaseModel):
    id: str
    waypoints: list[WaypointModel]
    theme: Theme
    rider_band: RiderBand
    start_date: datetime.date
    days: list[DayModel]
    total_distance_m: float
    total_elevation_gain_m: float

    @classmethod
    def from_trip(cls, trip: Trip) -> TripResponse:
        return cls(
            id=trip.id,
            waypoints=[WaypointModel.from_waypoint(w) for w in trip.waypoints],
            theme=trip.theme,
            rider_band=trip.rider_band,
            start_date=trip.start_date,
            days=[DayModel.from_day(d) for d in trip.days],
            total_distance_m=trip.total_distance_m,
            total_elevation_gain_m=trip.total_elevation_gain_m,
        )


class DayAlternativeResponse(BaseModel):
    """FR42 — current vs. proposed, for a ghost-vs-bold client comparison."""

    current: DayModel
    alternative: DayModel


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
    "DayAlternativeRequest",
    "DayAlternativeResponse",
    "DayModel",
    "DaySplitConfigModel",
    "ExportFormat",
    "GeocodeResponse",
    "HealthResponse",
    "LodgingOptionModel",
    "RouteGenerateRequest",
    "RouteResponse",
    "TripGenerateRequest",
    "TripResponse",
    "WaypointModel",
    "WeatherSummaryModel",
    "WeightOverrideModel",
]
