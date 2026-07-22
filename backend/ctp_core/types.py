"""Shared data types for ctp-core.

Pure data — no I/O, no FastAPI, no request/session concepts (Architecture P1).
"""

from __future__ import annotations

from dataclasses import dataclass, field
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


@dataclass
class Route:
    id: str
    theme: Theme
    shape: RouteShape
    coords: list[Coord]
    distance_m: float
    elevation_gain_m: float
