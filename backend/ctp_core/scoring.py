"""Theme scoring (ctp-core §5.2 `scoring/`).

The five MVP themes are not five algorithms — they are five WeightProfile
instances fed to one scoring function (PRD §5.1, Architecture §5.3).
"""

from __future__ import annotations

import logging
from collections.abc import Iterable, Sequence

from .providers import NodeDataProvider
from .types import BBox, Graph, Theme, WeightProfile

logger = logging.getLogger(__name__)

THEME_PROFILES: dict[Theme, WeightProfile] = {
    Theme.FLATTEST: WeightProfile(elevation_gain=-1.0),
    Theme.MOST_CLIMBING: WeightProfile(elevation_gain=1.0),
    Theme.LOWEST_TRAFFIC: WeightProfile(traffic_class=-1.0),
    Theme.FEWEST_TURNS: WeightProfile(turn_count=-1.0),
    Theme.MOST_ART: WeightProfile(
        poi_bonus={"tourism=artwork": 1.0, "historic=*": 1.0}, detour_budget=1.4
    ),
}

# Highway tag -> a coarse relative traffic-level proxy. Unlisted/unknown
# highway types default to a mid-level class (2).
_HIGHWAY_TRAFFIC_CLASS: dict[str, int] = {
    "motorway": 5,
    "motorway_link": 5,
    "trunk": 4,
    "trunk_link": 4,
    "primary": 4,
    "primary_link": 4,
    "secondary": 3,
    "secondary_link": 3,
    "tertiary": 2,
    "tertiary_link": 2,
    "unclassified": 2,
    "residential": 1,
    "living_street": 1,
    "service": 1,
    "cycleway": 0,
    "track": 0,
    "path": 0,
    "footway": 0,
}

# OSM `surface` tag -> a coarse paved(high)/unpaved(low) scale (FR12).
# Unlisted/unknown surfaces default to a mid-level class (2), the same
# "unknown = middling, not worst-case" convention `_highway_class` uses.
_SURFACE_SCORE: dict[str, int] = {
    "paved": 4,
    "asphalt": 4,
    "concrete": 4,
    "concrete:plates": 4,
    "concrete:lanes": 4,
    "paving_stones": 3,
    "sett": 3,
    "cobblestone": 3,
    "compacted": 2,
    "fine_gravel": 2,
    "gravel": 1,
    "dirt": 0,
    "ground": 0,
    "earth": 0,
    "grass": 0,
    "sand": 0,
    "mud": 0,
}

# Meters-equivalent scale for each weight signal, so a WeightProfile of
# magnitude 1.0 makes a real difference against typical edge lengths.
_ELEV_PENALTY_PER_M = 15.0
_TRAFFIC_PENALTY_PER_CLASS = 40.0
_TURN_PENALTY = 35.0
_POI_BONUS_PER_HIT = 150.0
_SURFACE_PENALTY_PER_CLASS = 40.0
_MIN_COST = 0.1


def _highway_class(edge_data: dict) -> int:
    highway = edge_data.get("highway")
    if isinstance(highway, list):
        highway = highway[0] if highway else None
    return _HIGHWAY_TRAFFIC_CLASS.get(highway, 2)


def _surface_class(edge_data: dict) -> int:
    surface = edge_data.get("surface")
    if isinstance(surface, list):
        surface = surface[0] if surface else None
    return _SURFACE_SCORE.get(surface, 2)


class WeightSchedule:
    """Resolves a WeightProfile per position along a trip, in cumulative
    trip-kilometers (PRD §5.1 seam 1).

    The M1 scalar themes only ever use the default (no overrides) — every
    position resolves to the same constant profile. FR13 (M5) is what makes
    this a real tour/day/segment lookup: overrides are pre-resolved
    (start_km, end_km, profile) ranges, first match wins. The solver and
    `score_edges` never learn the difference; only this class's resolution
    logic changed (Architecture §5.5)."""

    def __init__(
        self,
        default: WeightProfile,
        overrides: Sequence[tuple[float, float, WeightProfile]] = (),
    ):
        self._default = default
        self._overrides = list(overrides)

    @property
    def has_overrides(self) -> bool:
        return bool(self._overrides)

    def at(self, position_km: float = 0.0) -> WeightProfile:
        for start_km, end_km, profile in self._overrides:
            if start_km <= position_km < end_km:
                return profile
        return self._default


def score_edges(
    graph: Graph,
    schedule: WeightSchedule,
    bbox: BBox | None = None,
    providers: Iterable[NodeDataProvider] = (),
    positions_km: dict[int, float] | None = None,
) -> Graph:
    """Assign a `cost` to every edge from the theme's WeightProfile.

    `positions_km`, when given, maps each node to its estimated cumulative
    trip-km position — `ctp_core/trips.py` computes this once per leg via a
    Dijkstra walk (mirroring `routing.py`'s `_node_near_distance`) — so
    `weights.at()` is resolved per edge rather than once for the whole
    graph. This is what lets FR13's day/segment overrides actually vary the
    route. The M1 scalar case (single-route themes) omits `positions_km`,
    so every edge still resolves to the same constant profile via one
    `schedule.at(0.0)` call, exactly as before."""
    default_profile = schedule.at(0.0)

    node_bonus: dict[int, float] = {}
    # POI bonus always comes from the default profile — themed art/history
    # bonuses aren't part of FR13's day/segment override scope (elevation
    # and surface preference only, per PRD).
    art_weight = sum(default_profile.poi_bonus.values()) if default_profile.poi_bonus else 0.0
    if art_weight:
        providers = list(providers)
        if bbox is None:
            logger.warning("profile requests a POI bonus but no bbox was given — POI scoring skipped")
        elif not providers:
            logger.warning("profile requests a POI bonus but no providers were given — POI scoring skipped")
        else:
            for provider in providers:
                for node_id, score in provider.node_scores(graph, bbox).items():
                    node_bonus[node_id] = node_bonus.get(node_id, 0.0) + score

    for _u, v, _key, data in graph.edges(keys=True, data=True):
        profile = schedule.at(positions_km.get(v, 0.0)) if positions_km is not None else default_profile
        cost = data.get("length", 1.0)

        elev_gain = data.get("elev_gain", 0.0)
        cost -= profile.elevation_gain * elev_gain * _ELEV_PENALTY_PER_M

        traffic_class = _highway_class(data)
        cost -= profile.traffic_class * traffic_class * _TRAFFIC_PENALTY_PER_CLASS

        surface_class = _surface_class(data)
        cost -= profile.surface_preference * surface_class * _SURFACE_PENALTY_PER_CLASS

        if graph.nodes[v].get("street_count", 0) > 2:
            cost -= profile.turn_count * _TURN_PENALTY

        if node_bonus:
            cost -= node_bonus.get(v, 0.0) * art_weight * _POI_BONUS_PER_HIT

        data["cost"] = max(cost, _MIN_COST)

    return graph
