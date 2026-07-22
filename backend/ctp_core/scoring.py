"""Theme scoring (ctp-core §5.2 `scoring/`).

The five MVP themes are not five algorithms — they are five WeightProfile
instances fed to one scoring function (PRD §5.1, Architecture §5.3).
"""

from __future__ import annotations

from collections.abc import Iterable

from .providers import NodeDataProvider
from .types import BBox, Graph, Theme, WeightProfile

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

# Meters-equivalent scale for each weight signal, so a WeightProfile of
# magnitude 1.0 makes a real difference against typical edge lengths.
_ELEV_PENALTY_PER_M = 15.0
_TRAFFIC_PENALTY_PER_CLASS = 40.0
_TURN_PENALTY = 35.0
_POI_BONUS_PER_HIT = 150.0
_MIN_COST = 0.1


def _highway_class(edge_data: dict) -> int:
    highway = edge_data.get("highway")
    if isinstance(highway, list):
        highway = highway[0] if highway else None
    return _HIGHWAY_TRAFFIC_CLASS.get(highway, 2)


class WeightSchedule:
    """Resolves a WeightProfile per edge position (PRD §5.1 seam 1).

    M1 always returns the same constant profile — FR13 (M5) extends `at()`
    to a real tour/day/segment lookup without the solver ever learning the
    difference (Architecture §5.5)."""

    def __init__(self, profile: WeightProfile):
        self._profile = profile

    def at(self, position: float) -> WeightProfile:
        del position  # constant in M1; FR13 makes this a real lookup
        return self._profile


def score_edges(
    graph: Graph,
    schedule: WeightSchedule,
    bbox: BBox | None = None,
    providers: Iterable[NodeDataProvider] = (),
) -> Graph:
    """Assign a `cost` to every edge from the theme's WeightProfile.

    `weights.at(position)` is looked up once per edge, not once per solve —
    in the M1 scalar case every edge resolves to the same profile, which is
    exactly what lets FR13 become a one-function change later."""
    profile = schedule.at(0.0)

    node_bonus: dict[int, float] = {}
    art_weight = sum(profile.poi_bonus.values()) if profile.poi_bonus else 0.0
    if art_weight and bbox is not None:
        for provider in providers:
            for node_id, score in provider.node_scores(graph, bbox).items():
                node_bonus[node_id] = node_bonus.get(node_id, 0.0) + score

    for _u, v, _key, data in graph.edges(keys=True, data=True):
        cost = data.get("length", 1.0)

        elev_gain = data.get("elev_gain", 0.0)
        cost -= profile.elevation_gain * elev_gain * _ELEV_PENALTY_PER_M

        traffic_class = _highway_class(data)
        cost -= profile.traffic_class * traffic_class * _TRAFFIC_PENALTY_PER_CLASS

        if graph.nodes[v].get("street_count", 0) > 2:
            cost -= profile.turn_count * _TURN_PENALTY

        if node_bonus:
            cost -= node_bonus.get(v, 0.0) * art_weight * _POI_BONUS_PER_HIT

        data["cost"] = max(cost, _MIN_COST)

    return graph
