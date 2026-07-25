import datetime

import networkx as nx
import pytest

from ctp_core.providers import OsmArtHistoryProvider
from ctp_core.scoring import THEME_PROFILES
from ctp_core.trips import _regroup_cautions, default_day_split, propose_day_alternative, solve_trip
from ctp_core.types import Coord, DaySplitConfig, RiderBand, Theme, Waypoint, WeightOverride, WeightProfile

START = Coord(lat=35.6841, lon=-82.0091)
MID = Coord(lat=35.690, lon=-82.005)
END = Coord(lat=35.695, lon=-82.010)
START_DATE = datetime.date(2026, 6, 1)
WAYPOINTS = [Waypoint(coord=START), Waypoint(coord=MID), Waypoint(coord=END)]


class _NullLodgingProvider:
    """No real Overpass calls -- these tests are about trips.py's own
    day-splitting/override logic, not OsmLodgingProvider's OSM query
    behavior (already exercised manually against the real dev bbox)."""

    def options_near(self, coord, radius_m):
        del coord, radius_m
        return []


def _solve(base_graph, bbox, **overrides):
    kwargs = dict(
        theme=Theme.FLATTEST,
        tour_profile=THEME_PROFILES[Theme.FLATTEST],
        overrides=[],
        rider_band=RiderBand.SOLO,
        lodging_provider=_NullLodgingProvider(),
        weather_provider=None,
        bbox=bbox,
        start_date=START_DATE,
        day_split=DaySplitConfig(min_daily_km=0.1, max_daily_km=500.0),
    )
    kwargs.update(overrides)
    return solve_trip(base_graph.copy(), WAYPOINTS, **kwargs)


def test_solve_trip_requires_at_least_two_waypoints(base_graph, bbox):
    with pytest.raises(ValueError):
        solve_trip(
            base_graph.copy(),
            [Waypoint(coord=START)],
            theme=Theme.FLATTEST,
            tour_profile=THEME_PROFILES[Theme.FLATTEST],
            overrides=[],
            rider_band=RiderBand.SOLO,
            lodging_provider=_NullLodgingProvider(),
            weather_provider=None,
            bbox=bbox,
            start_date=START_DATE,
        )


def test_whole_trip_fits_in_one_day_when_caps_are_generous(base_graph, bbox):
    trip = _solve(base_graph, bbox, day_split=DaySplitConfig(min_daily_km=0.1, max_daily_km=500.0))
    assert len(trip.days) == 1
    assert trip.total_distance_m == pytest.approx(trip.days[0].distance_m)


def test_tight_distance_cap_splits_into_multiple_days_within_cap(base_graph, bbox):
    max_km = 1.0
    trip = _solve(base_graph, bbox, day_split=DaySplitConfig(min_daily_km=0.1, max_daily_km=max_km))
    assert len(trip.days) > 1
    for day in trip.days[:-1]:
        # every day but a possible final remainder should be within the cap
        # (the greedy split packs as far as possible without exceeding it)
        assert day.distance_m / 1000.0 <= max_km + 1e-6


def test_elevation_cap_can_bind_before_distance_cap(base_graph, bbox):
    # An elevation cap of 0m forces a cut at the first edge with any gain at
    # all -- proves the elevation cap is actually consulted, not just
    # distance.
    trip = _solve(
        base_graph,
        bbox,
        day_split=DaySplitConfig(min_daily_km=0.1, max_daily_km=500.0, max_daily_elevation_m=0.0),
    )
    if trip.days[0].elevation_gain_m > 0:
        assert len(trip.days) > 1


def test_day_dates_and_indices_are_sequential(base_graph, bbox):
    trip = _solve(base_graph, bbox, day_split=DaySplitConfig(min_daily_km=0.1, max_daily_km=1.0))
    assert trip.start_date == START_DATE
    assert len(trip.days) > 1  # otherwise this test proves nothing about sequencing
    assert [day.index for day in trip.days] == list(range(len(trip.days)))


def test_surface_preference_override_still_produces_a_valid_trip(base_graph, bbox):
    # Not asserting the two routes differ (this small bbox may have no
    # unpaved alternative at all) -- only that a day-scoped override never
    # breaks the solve and still produces a valid, fully-covering trip.
    override = WeightOverride(day_index=0, profile=WeightProfile(surface_preference=-1.0))
    overridden = _solve(base_graph, bbox, overrides=[override])
    assert overridden.total_distance_m > 0
    assert len(overridden.days) >= 1


def test_out_of_range_override_day_index_raises(base_graph, bbox):
    override = WeightOverride(day_index=99, profile=WeightProfile(elevation_gain=1.0))
    with pytest.raises(ValueError):
        _solve(base_graph, bbox, overrides=[override])


def test_default_day_split_shrinks_with_larger_rider_bands():
    solo = default_day_split(RiderBand.SOLO)
    small = default_day_split(RiderBand.SMALL_GROUP)
    large = default_day_split(RiderBand.LARGE_GROUP)
    assert solo.max_daily_km > small.max_daily_km > large.max_daily_km


def test_regroup_cautions_empty_for_solo_riders(base_graph, bbox):
    trip = _solve(base_graph, bbox)
    for day in trip.days:
        assert day.regroup_cautions == []


def test_propose_day_alternative_does_not_mutate_the_stored_trip(base_graph, bbox):
    trip = _solve(base_graph, bbox, day_split=DaySplitConfig(min_daily_km=0.1, max_daily_km=1.0))
    original_days = list(trip.days)
    original_first_day_distance = trip.days[0].distance_m

    alternative = propose_day_alternative(
        base_graph.copy(),
        trip,
        day_index=0,
        alt_profile=WeightProfile(surface_preference=1.0),
        lodging_provider=_NullLodgingProvider(),
        weather_provider=None,
        bbox=bbox,
        start_date=START_DATE,
        providers=[OsmArtHistoryProvider()],
    )

    assert trip.days == original_days
    assert trip.days[0].distance_m == pytest.approx(original_first_day_distance)
    assert alternative.index == 0
    assert alternative.distance_m > 0


def test_propose_day_alternative_rejects_unknown_day_index(base_graph, bbox):
    trip = _solve(base_graph, bbox)
    with pytest.raises(ValueError):
        propose_day_alternative(
            base_graph.copy(),
            trip,
            day_index=99,
            alt_profile=WeightProfile(),
            lodging_provider=_NullLodgingProvider(),
            weather_provider=None,
            bbox=bbox,
            start_date=START_DATE,
        )


# FR46 -- regroup cautions, on synthetic graphs (the real dev bbox has no
# `surface`/`width` OSM tags at all, so these behaviors are otherwise
# untested by the fixture-backed tests above).


def _line_graph(edges):
    """edges: list of (u, v, length_m, surface, width) -- builds a simple
    directed path graph carrying just the attributes _regroup_cautions
    reads."""
    graph = nx.MultiDiGraph()
    for u, v, length_m, surface, width in edges:
        data = {"length": length_m, "cost": length_m}
        if surface is not None:
            data["surface"] = surface
        if width is not None:
            data["width"] = width
        graph.add_edge(u, v, 0, **data)
    return graph


def test_regroup_cautions_flags_a_long_unpaved_run_for_a_group():
    graph = _line_graph(
        [
            (1, 2, 200.0, "asphalt", None),
            (2, 3, 300.0, "gravel", None),
            (3, 4, 300.0, "gravel", None),  # 600m combined -- over the 500m threshold
            (4, 5, 200.0, "asphalt", None),
        ]
    )
    cautions = _regroup_cautions(graph, [1, 2, 3, 4, 5], RiderBand.LARGE_GROUP)
    assert len(cautions) == 1
    assert "Narrow/unpaved" in cautions[0]


def test_regroup_cautions_ignores_a_short_unpaved_run():
    graph = _line_graph(
        [
            (1, 2, 200.0, "asphalt", None),
            (2, 3, 100.0, "gravel", None),  # below the 500m threshold
            (3, 4, 200.0, "asphalt", None),
        ]
    )
    assert _regroup_cautions(graph, [1, 2, 3, 4], RiderBand.LARGE_GROUP) == []


def test_regroup_cautions_flags_a_narrow_paved_run_by_width():
    graph = _line_graph(
        [
            (1, 2, 200.0, "asphalt", None),
            (2, 3, 600.0, "asphalt", 2.0),  # paved but narrower than 3m
            (3, 4, 200.0, "asphalt", None),
        ]
    )
    cautions = _regroup_cautions(graph, [1, 2, 3, 4], RiderBand.LARGE_GROUP)
    assert len(cautions) == 1


def test_regroup_cautions_empty_for_solo_even_with_a_long_unpaved_run():
    graph = _line_graph([(1, 2, 600.0, "gravel", None)])
    assert _regroup_cautions(graph, [1, 2], RiderBand.SOLO) == []


def test_regroup_cautions_flushes_a_trailing_unpaved_run_at_path_end():
    graph = _line_graph(
        [
            (1, 2, 200.0, "asphalt", None),
            (2, 3, 600.0, "gravel", None),
        ]
    )
    cautions = _regroup_cautions(graph, [1, 2, 3], RiderBand.LARGE_GROUP)
    assert len(cautions) == 1
