import itertools

import pytest

from ctp_core.providers import OsmArtHistoryProvider
from ctp_core.routing import solve_route
from ctp_core.scoring import THEME_PROFILES, WeightSchedule, score_edges
from ctp_core.types import Coord, RouteShape, Theme

START = Coord(lat=35.6841, lon=-82.0091)
DESTINATION = Coord(lat=35.695, lon=-82.010)


@pytest.mark.parametrize("theme,shape", list(itertools.product(Theme, RouteShape)))
def test_solve_route_produces_a_valid_route_for_every_theme_and_shape(base_graph, bbox, theme, shape):
    schedule = WeightSchedule(THEME_PROFILES[theme])
    graph = score_edges(base_graph.copy(), schedule, bbox=bbox, providers=[OsmArtHistoryProvider()])

    kwargs = {"end": DESTINATION} if shape is RouteShape.POINT_TO_POINT else {"end": None, "target_distance_km": 4.0}

    route = solve_route(graph, START, shape=shape, theme=theme, cpus=2, **kwargs)

    assert route.theme is theme
    assert route.shape is shape
    assert len(route.coords) >= 2
    assert route.distance_m > 0
    assert route.elevation_gain_m >= 0


def test_point_to_point_without_end_raises(base_graph, bbox):
    graph = score_edges(base_graph.copy(), WeightSchedule(THEME_PROFILES[Theme.FLATTEST]), bbox=bbox)
    with pytest.raises(ValueError):
        solve_route(graph, START, end=None, shape=RouteShape.POINT_TO_POINT, theme=Theme.FLATTEST, cpus=1)


@pytest.mark.parametrize("shape", [RouteShape.LOOP, RouteShape.OUT_AND_BACK])
def test_loop_and_out_and_back_without_target_or_end_raises(base_graph, bbox, shape):
    graph = score_edges(base_graph.copy(), WeightSchedule(THEME_PROFILES[Theme.FLATTEST]), bbox=bbox)
    with pytest.raises(ValueError):
        solve_route(graph, START, end=None, shape=shape, theme=Theme.FLATTEST, cpus=1)


def test_out_and_back_retraces_the_same_outbound_and_return_path(base_graph, bbox):
    graph = score_edges(base_graph.copy(), WeightSchedule(THEME_PROFILES[Theme.FLATTEST]), bbox=bbox)
    route = solve_route(
        graph, START, end=None, shape=RouteShape.OUT_AND_BACK, theme=Theme.FLATTEST, cpus=1, target_distance_km=4.0
    )
    half = len(route.coords) // 2
    outbound = route.coords[: half + 1]
    inbound = list(reversed(route.coords[half:]))
    assert [(c.lat, c.lon) for c in outbound] == [(c.lat, c.lon) for c in inbound]
