"""Shared data types for ctp-core.

Pure data — no I/O, no FastAPI, no request/session concepts (Architecture P1).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from enum import Enum

import networkx as nx

Graph = nx.MultiDiGraph


@dataclass(frozen=True)
class Coord:
    lat: float
    lon: float


@dataclass(frozen=True)
class BBox:
    """west, south, east, north — matches osmnx's bbox argument order."""

    west: float
    south: float
    east: float
    north: float

    def as_tuple(self) -> tuple[float, float, float, float]:
        return (self.west, self.south, self.east, self.north)


class Theme(str, Enum):
    FLATTEST = "flattest"
    MOST_CLIMBING = "most_climbing"
    LOWEST_TRAFFIC = "lowest_traffic"
    FEWEST_TURNS = "fewest_turns"
    MOST_ART = "most_art"


class RouteShape(str, Enum):
    LOOP = "loop"
    OUT_AND_BACK = "out_and_back"
    POINT_TO_POINT = "point_to_point"


class ExportFormat(str, Enum):
    GPX = "gpx"
    TCX = "tcx"
    FIT = "fit"


@dataclass(frozen=True)
class WeightProfile:
    """One instance per theme (PRD §5.1, Architecture §5.3) fed to a single
    scoring function rather than one algorithm per theme."""

    elevation_gain: float = 0.0  # negative = avoid climbing, positive = seek it
    traffic_class: float = 0.0  # negative = avoid traffic
    turn_count: float = 0.0  # negative = avoid decision points
    poi_bonus: dict[str, float] = field(default_factory=dict)  # {"tourism=artwork": 2.0}
    detour_budget: float = 1.15  # max multiple of the shortest-path baseline
    surface_preference: float = 0.0  # FR12/FR13: negative = avoid unpaved, positive = seek it


@dataclass
class Route:
    id: str
    theme: Theme
    shape: RouteShape
    coords: list[Coord]
    distance_m: float
    elevation_gain_m: float


class RiderBand(str, Enum):
    """FR46 — a trip's group size, coarse on purpose (PRD only asks for
    "solo through large organized group"), used to seed day mileage/climb
    defaults and to flag narrow/gravel stretches for larger groups."""

    SOLO = "solo"
    SMALL_GROUP = "small_group"
    LARGE_GROUP = "large_group"


@dataclass(frozen=True)
class Waypoint:
    """FR10 — a point a multi-day route must honor. The route still
    optimizes for the selected theme *between* consecutive waypoints."""

    coord: Coord
    label: str | None = None


@dataclass(frozen=True)
class DaySplitConfig:
    """FR11 — min/max daily mileage and elevation caps driving day splitting."""

    min_daily_km: float
    max_daily_km: float
    max_daily_elevation_m: float | None = None


@dataclass(frozen=True)
class WeightOverride:
    """FR13 — a day- or partial-day-segment-scoped WeightProfile override.
    `segment_start_km`/`segment_end_km` are offsets into that day (None on
    both means the whole day)."""

    day_index: int
    profile: WeightProfile
    segment_start_km: float | None = None
    segment_end_km: float | None = None


@dataclass
class LodgingOption:
    """FR14 — a lodging/campground option near a day's end point, sourced
    from OSM tags (no dedicated data source needed)."""

    name: str
    kind: str  # "hotel" | "motel" | "guest_house" | "camp_site"
    coord: Coord
    distance_from_day_end_m: float


@dataclass
class WeatherSummary:
    """FR15 — seasonal-norms weather for one day of a trip, averaged over
    several past years at the same calendar day (not a specific-date
    forecast — that's the separate Weather Forecast feature at M7)."""

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
    pollen: dict[str, float] | None  # e.g. {"grass": 12.0} -- Open-Meteo's pollen
    # coverage is Europe-only; None outside that domain (dev bbox is NC, US)


@dataclass
class Day:
    """One day of a multi-day Trip."""

    index: int
    coords: list[Coord]
    distance_m: float
    elevation_gain_m: float
    surface_breakdown_m: dict[str, float]  # FR12 — OSM `surface` tag -> meters
    lodging_options: list[LodgingOption]  # FR14
    weather: WeatherSummary | None  # FR15
    regroup_cautions: list[str]  # FR46


@dataclass
class Trip:
    """A multi-day tour: an ordered chain of waypoint-to-waypoint legs
    (FR10), split into calendar days (FR11)."""

    id: str
    waypoints: list[Waypoint]
    theme: Theme
    tour_profile: WeightProfile
    overrides: list[WeightOverride]
    rider_band: RiderBand
    start_date: date
    days: list[Day]
    total_distance_m: float
    total_elevation_gain_m: float
