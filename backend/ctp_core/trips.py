"""Multi-day trip solving (ctp-core §5.2 `trips/`, ROADMAP Leg 3 / PRD M5).

Turns an ordered chain of waypoints (FR10) into a `Trip`: waypoint-to-
waypoint legs solved and concatenated, split into calendar days (FR11),
with optional day/segment weight overrides (FR13) that re-solve the whole
trip once more under a position-aware `WeightSchedule` — never a new
solver, exactly what Architecture §5.5 promises. Surface breakdown (FR12),
lodging (FR14), regroup cautions (FR46), and weather (FR15) are attached
per finished day.
"""

from __future__ import annotations

import datetime
import uuid
from collections.abc import Iterable

from .providers import NodeDataProvider, OsmLodgingProvider
from .routing import _distances_from, _nearest_node, _path_geometry, _shortest_path
from .scoring import WeightSchedule, score_edges
from .types import (
    BBox,
    Day,
    DaySplitConfig,
    Graph,
    RiderBand,
    Theme,
    Trip,
    Waypoint,
    WeightOverride,
    WeightProfile,
)
from .weather import WeatherProvider

# FR46 — group size seeds a default daily-distance cap when the caller
# doesn't supply a DaySplitConfig explicitly; still overridable by an
# explicit config or FR13 (PRD: "seeds day mileage/climb defaults, still
# overridable").
_DEFAULT_MAX_DAILY_KM: dict[RiderBand, float] = {
    RiderBand.SOLO: 120.0,
    RiderBand.SMALL_GROUP: 90.0,
    RiderBand.LARGE_GROUP: 70.0,
}
_DEFAULT_MIN_DAILY_KM = 40.0

# FR14 — how far from a day's end point to look for lodging/campground options.
_LODGING_SEARCH_RADIUS_M = 3000.0

# FR46 — a regroup caution is raised for any unpaved-or-narrow run at least
# this long.
_CAUTION_MIN_RUN_M = 500.0
_NARROW_WIDTH_M = 3.0
_UNPAVED_SURFACES = {"gravel", "fine_gravel", "dirt", "ground", "earth", "grass", "sand", "mud"}


def default_day_split(rider_band: RiderBand) -> DaySplitConfig:
    """FR46's rider-band-seeded default, used by `solve_trip` when the
    caller doesn't supply a `DaySplitConfig`."""
    return DaySplitConfig(min_daily_km=_DEFAULT_MIN_DAILY_KM, max_daily_km=_DEFAULT_MAX_DAILY_KM[rider_band])


def _edge_between(graph: Graph, u: int, v: int) -> dict:
    return min(graph[u][v].values(), key=lambda d: d.get("cost", float("inf")))


def _surface_tag(edge_data: dict) -> str | None:
    surface = edge_data.get("surface")
    if isinstance(surface, list):
        surface = surface[0] if surface else None
    return surface


def _is_narrow(edge_data: dict) -> bool:
    width = edge_data.get("width")
    if isinstance(width, list):
        width = width[0] if width else None
    try:
        return width is not None and float(width) < _NARROW_WIDTH_M
    except (TypeError, ValueError):
        return False


def _solve_full_path(
    graph: Graph,
    waypoints: list[Waypoint],
    schedule: WeightSchedule,
    bbox: BBox,
    providers: Iterable[NodeDataProvider],
) -> tuple[list[int], list[tuple[float, float]]]:
    """Solves each waypoint-to-waypoint leg (FR10) in order, concatenating
    into one continuous node path with an index-aligned array of
    (cumulative_km, cumulative_elevation_gain_m).

    When `schedule` has no overrides, every edge resolves to the same
    profile regardless of position — score once, cheap, exactly M1's
    behavior. When it does (FR13), each leg is re-scored with a real
    per-edge position: `leg_start_km` plus a Dijkstra walk from the leg's
    own start node (`routing.py`'s `_distances_from` — the same distance
    primitive `_node_near_distance` already uses for turnaround search), so
    `weights.at()` sees each edge's actual cumulative trip position. This
    re-scores every leg uniformly rather than pre-computing which legs an
    override "affects" — a leg with no applicable override still resolves
    to the same default profile at every position, so the result is
    identical either way, without needing a second bookkeeping path."""
    if not schedule.has_overrides:
        score_edges(graph, schedule, bbox=bbox, providers=providers)

    full_path: list[int] = []
    cumulative: list[tuple[float, float]] = []
    running_km = 0.0
    running_elev = 0.0

    for wp_start, wp_end in zip(waypoints, waypoints[1:]):
        start_node = _nearest_node(graph, wp_start.coord)
        end_node = _nearest_node(graph, wp_end.coord)

        if schedule.has_overrides:
            distances_m = _distances_from(graph, start_node)
            positions_km = {n: running_km + d / 1000.0 for n, d in distances_m.items()}
            score_edges(graph, schedule, bbox=bbox, providers=providers, positions_km=positions_km)

        leg_path = _shortest_path(graph, start_node, end_node)

        if not full_path:
            full_path.append(leg_path[0])
            cumulative.append((0.0, 0.0))

        for u, v in zip(leg_path, leg_path[1:]):
            edge_data = _edge_between(graph, u, v)
            running_km += edge_data.get("length", 0.0) / 1000.0
            running_elev += edge_data.get("elev_gain", 0.0)
            full_path.append(v)
            cumulative.append((running_km, running_elev))

    return full_path, cumulative


def _split_into_days(
    full_path: list[int], cumulative: list[tuple[float, float]], day_split: DaySplitConfig
) -> list[tuple[int, int]]:
    """FR11 — greedy day-boundary split, returned as (start_idx, end_idx)
    index pairs into `full_path`/`cumulative`.

    Advances a day as far as possible while staying within `max_daily_km`
    and `max_daily_elevation_m`; `min_daily_km` is a soft target only —
    there's no requirement in the PRD to cut a day short to hit it, only
    caps to respect. Resolved default for an otherwise unspecified priority
    order between the two caps: whichever binds first ends the day. A
    single edge that alone exceeds a cap still can't produce a zero-length
    day, so it's included rather than dropped — surfacing that conflict to
    the rider is FR43's job (not built in this leg), not this function's."""
    n = len(full_path)
    max_km = day_split.max_daily_km
    max_elev = day_split.max_daily_elevation_m

    days: list[tuple[int, int]] = []
    day_start = 0
    while day_start < n - 1:
        day_start_km, day_start_elev = cumulative[day_start]
        cut = day_start
        for j in range(day_start + 1, n):
            dist_km = cumulative[j][0] - day_start_km
            elev_m = cumulative[j][1] - day_start_elev
            if dist_km > max_km or (max_elev is not None and elev_m > max_elev):
                break
            cut = j
        if cut == day_start:
            cut = day_start + 1
        days.append((day_start, cut))
        day_start = cut

    return days


def _resolve_overrides(
    overrides: list[WeightOverride], day_ranges_km: list[tuple[float, float]]
) -> list[tuple[float, float, WeightProfile]]:
    """Resolves each FR13 day/segment override to an absolute
    (start_km, end_km, profile) range in trip-cumulative kilometers."""
    resolved: list[tuple[float, float, WeightProfile]] = []
    for override in overrides:
        if not 0 <= override.day_index < len(day_ranges_km):
            raise ValueError(f"weight override references day {override.day_index}, but the trip has {len(day_ranges_km)} day(s)")
        day_start_km, day_end_km = day_ranges_km[override.day_index]
        start_km = day_start_km + (override.segment_start_km or 0.0)
        end_km = day_start_km + override.segment_end_km if override.segment_end_km is not None else day_end_km
        resolved.append((start_km, end_km, override.profile))
    return resolved


def _surface_breakdown(graph: Graph, path: list[int]) -> dict[str, float]:
    breakdown: dict[str, float] = {}
    for u, v in zip(path, path[1:]):
        edge_data = _edge_between(graph, u, v)
        tag = _surface_tag(edge_data) or "unknown"
        breakdown[tag] = breakdown.get(tag, 0.0) + edge_data.get("length", 0.0)
    return breakdown


def _regroup_cautions(graph: Graph, path: list[int], rider_band: RiderBand) -> list[str]:
    """FR46 — flags narrow/unpaved runs long enough to matter for a group,
    with a rough km marker into the day. Solo riders get no cautions."""
    if rider_band is RiderBand.SOLO:
        return []

    cautions: list[str] = []
    cum_km = 0.0
    run_m = 0.0
    run_start_km = 0.0

    def _flush(end_km: float) -> None:
        if run_m >= _CAUTION_MIN_RUN_M:
            cautions.append(
                f"Narrow/unpaved stretch near km {run_start_km:.1f}–{end_km:.1f} "
                "— consider regroup points for larger groups."
            )

    for u, v in zip(path, path[1:]):
        edge_data = _edge_between(graph, u, v)
        length_m = edge_data.get("length", 0.0)
        flagged = _surface_tag(edge_data) in _UNPAVED_SURFACES or _is_narrow(edge_data)
        if flagged:
            if run_m == 0.0:
                run_start_km = cum_km
            run_m += length_m
        else:
            _flush(cum_km)
            run_m = 0.0
        cum_km += length_m / 1000.0

    _flush(cum_km)
    return cautions


def solve_trip(
    graph: Graph,
    waypoints: list[Waypoint],
    theme: Theme,
    tour_profile: WeightProfile,
    overrides: list[WeightOverride],
    rider_band: RiderBand,
    lodging_provider: OsmLodgingProvider,
    weather_provider: WeatherProvider | None,
    bbox: BBox,
    start_date: datetime.date,
    day_split: DaySplitConfig | None = None,
    providers: Iterable[NodeDataProvider] = (),
) -> Trip:
    """Solve a multi-day Trip end to end (FR10/FR11/FR12/FR13/FR14/FR15/FR46).

    `graph` is mutated in place (its edges' `cost` gets overwritten,
    possibly more than once for FR13's re-solve pass) — same convention as
    `solve_route`/`score_edges`: the caller passes an already-copied graph
    (e.g. `app.state.graph_base.copy()`), this module never copies it
    itself.

    `weather_provider` is optional so callers/tests that don't want a
    network dependency can pass `None` — each Day's `weather` is then just
    `None`, the same graceful-degradation posture used throughout this
    module rather than failing the whole trip over one optional signal."""
    if len(waypoints) < 2:
        raise ValueError("a trip needs at least two waypoints (a start and an end)")

    day_split = day_split or default_day_split(rider_band)
    working = graph

    # Pass 1 (FR10): tour-default profile only, no overrides yet.
    tour_schedule = WeightSchedule(tour_profile)
    full_path, cumulative = _solve_full_path(working, waypoints, tour_schedule, bbox, providers)

    # Day split (FR11).
    day_slices = _split_into_days(full_path, cumulative, day_split)

    # Pass 2 (FR13) — only if the caller actually scoped any overrides.
    if overrides:
        day_ranges_km = [(cumulative[s][0], cumulative[e][0]) for s, e in day_slices]
        resolved = _resolve_overrides(overrides, day_ranges_km)
        full_schedule = WeightSchedule(tour_profile, resolved)
        full_path, cumulative = _solve_full_path(working, waypoints, full_schedule, bbox, providers)
        # Bounded re-split — one more pass, not a convergence loop; "close
        # enough" is fine here, this isn't a hard optimization problem.
        day_slices = _split_into_days(full_path, cumulative, day_split)

    days: list[Day] = []
    day_date = start_date
    for index, (start_idx, end_idx) in enumerate(day_slices):
        day_path = full_path[start_idx : end_idx + 1]
        coords, distance_m, elevation_gain_m = _path_geometry(working, day_path)
        weather = (
            weather_provider.seasonal_norms_at(coords[0], day_date.month, day_date.day)
            if weather_provider is not None
            else None
        )
        days.append(
            Day(
                index=index,
                coords=coords,
                distance_m=distance_m,
                elevation_gain_m=elevation_gain_m,
                surface_breakdown_m=_surface_breakdown(working, day_path),
                lodging_options=lodging_provider.options_near(coords[-1], _LODGING_SEARCH_RADIUS_M),
                weather=weather,
                regroup_cautions=_regroup_cautions(working, day_path, rider_band),
            )
        )
        day_date += datetime.timedelta(days=1)

    return Trip(
        id=str(uuid.uuid4()),
        waypoints=waypoints,
        theme=theme,
        tour_profile=tour_profile,
        overrides=overrides,
        rider_band=rider_band,
        start_date=start_date,
        days=days,
        total_distance_m=sum(day.distance_m for day in days),
        total_elevation_gain_m=sum(day.elevation_gain_m for day in days),
    )


def propose_day_alternative(
    graph: Graph,
    trip: Trip,
    day_index: int,
    alt_profile: WeightProfile,
    lodging_provider: OsmLodgingProvider,
    weather_provider: WeatherProvider | None,
    bbox: BBox,
    start_date: datetime.date,
    providers: Iterable[NodeDataProvider] = (),
    segment_start_km: float | None = None,
    segment_end_km: float | None = None,
) -> Day:
    """FR42 — proposes an alternative for one day under a different weight
    profile, sharing that day's original start/end waypoints, **without
    mutating `trip`**. The caller (ctp_service) shows this alongside the
    current day (ghost vs. bold) and only commits it via a separate
    "make active" call — nothing here writes back to the stored trip."""
    if not 0 <= day_index < len(trip.days):
        raise ValueError(f"trip has no day {day_index}")

    day = trip.days[day_index]
    start_wp = Waypoint(coord=day.coords[0])
    end_wp = Waypoint(coord=day.coords[-1])

    override = WeightOverride(
        day_index=0,
        profile=alt_profile,
        segment_start_km=segment_start_km,
        segment_end_km=segment_end_km,
    )
    alt_trip = solve_trip(
        graph,
        waypoints=[start_wp, end_wp],
        theme=trip.theme,
        tour_profile=trip.tour_profile,
        overrides=[override],
        rider_band=trip.rider_band,
        lodging_provider=lodging_provider,
        weather_provider=weather_provider,
        bbox=bbox,
        start_date=start_date + datetime.timedelta(days=day_index),
        day_split=DaySplitConfig(min_daily_km=0.0, max_daily_km=float("inf")),
        providers=providers,
    )
    alternative = alt_trip.days[0]
    return Day(
        index=day_index,
        coords=alternative.coords,
        distance_m=alternative.distance_m,
        elevation_gain_m=alternative.elevation_gain_m,
        surface_breakdown_m=alternative.surface_breakdown_m,
        lodging_options=alternative.lodging_options,
        weather=alternative.weather,
        regroup_cautions=alternative.regroup_cautions,
    )
