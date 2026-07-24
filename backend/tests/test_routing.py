import itertools

import networkx as nx
import pytest
from shapely.geometry import LineString

from ctp_core.providers import OsmArtHistoryProvider
from ctp_core.routing import (
    _edge_coords,
    _nearest_node,
    _node_near_distance,
    _path_geometry,
    _shortest_path,
    _shortest_path_avoiding_edges,
    solve_route,
)
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
    if shape in (RouteShape.LOOP, RouteShape.OUT_AND_BACK):
        assert (route.coords[0].lat, route.coords[0].lon) == (route.coords[-1].lat, route.coords[-1].lon)


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


def test_node_near_distance_prefers_different_turnaround_nodes_per_theme(base_graph, bbox):
    start_node = _nearest_node(base_graph, START)
    picked_nodes = set()
    for theme in Theme:
        graph = score_edges(base_graph.copy(), WeightSchedule(THEME_PROFILES[theme]), bbox=bbox)
        picked_nodes.add(_node_near_distance(graph, start_node, 2000.0))
    assert len(picked_nodes) > 1


def test_loop_avoids_a_pure_retrace_when_an_alternative_route_exists(base_graph, bbox):
    # 1.5km is a target distance where this bbox's road network genuinely
    # offers an alternative return route (verified directly against
    # _shortest_path_avoiding_edges before writing this test) — unlike some
    # other target distances near a dead-end spur, where retracing is the
    # only physically correct route and the fallback path is expected.
    graph = score_edges(base_graph.copy(), WeightSchedule(THEME_PROFILES[Theme.FLATTEST]), bbox=bbox)
    start_node = _nearest_node(graph, START)
    turnaround_node = _node_near_distance(graph, start_node, 750.0)
    leg_out = _shortest_path(graph, start_node, turnaround_node)
    out_coords, _out_distance_m, _out_elevation_m = _path_geometry(graph, leg_out)
    retrace_coords = [(c.lat, c.lon) for c in out_coords + list(reversed(out_coords))[1:]]

    route = solve_route(
        graph, START, end=None, shape=RouteShape.LOOP, theme=Theme.FLATTEST, cpus=1, target_distance_km=1.5
    )
    assert [(c.lat, c.lon) for c in route.coords] != retrace_coords


def test_shortest_path_avoiding_edges_returns_none_on_a_dead_end_spur():
    graph = nx.MultiDiGraph()
    # 1 -- 2 -- 3: the only way from 3 back to 1 is back through 2.
    graph.add_edge(1, 2, 0, cost=1.0)
    graph.add_edge(2, 1, 0, cost=1.0)
    graph.add_edge(2, 3, 0, cost=1.0)
    graph.add_edge(3, 2, 0, cost=1.0)

    avoid = {frozenset((1, 2)), frozenset((2, 3))}
    assert _shortest_path_avoiding_edges(graph, 3, 1, avoid) is None
    # The graph must be restored after the failed attempt.
    assert graph.has_edge(3, 2, 0)
    assert graph.has_edge(2, 1, 0)


def test_shortest_path_avoiding_edges_finds_a_real_alternative():
    graph = nx.MultiDiGraph()
    # A triangle: 1-2-3-1. Direct edge 3->1 exists, plus a longer way via 2.
    graph.add_edge(1, 2, 0, cost=1.0)
    graph.add_edge(2, 1, 0, cost=1.0)
    graph.add_edge(2, 3, 0, cost=1.0)
    graph.add_edge(3, 2, 0, cost=1.0)
    graph.add_edge(3, 1, 0, cost=1.0)
    graph.add_edge(1, 3, 0, cost=1.0)

    avoid = {frozenset((1, 2))}
    path = _shortest_path_avoiding_edges(graph, 1, 2, avoid)
    assert path == [1, 3, 2]
    # The avoided edge must be restored afterward.
    assert graph.has_edge(1, 2, 0)


def test_path_geometry_follows_edge_geometry_when_present(base_graph):
    u, v, key, data = next(
        (u, v, key, data)
        for u, v, key, data in base_graph.edges(keys=True, data=True)
        if data.get("geometry") is not None
    )
    coords = _edge_coords(base_graph, u, v, data)
    assert len(coords) > 2
    assert (coords[0].lat, coords[0].lon) == (base_graph.nodes[u]["y"], base_graph.nodes[u]["x"])
    assert (coords[-1].lat, coords[-1].lon) == (base_graph.nodes[v]["y"], base_graph.nodes[v]["x"])


def test_path_geometry_falls_back_to_a_chord_without_edge_geometry(base_graph):
    u, v, data = next(iter(base_graph.edges(data=True)))
    data_without_geometry = {k: val for k, val in data.items() if k != "geometry"}
    coords = _edge_coords(base_graph, u, v, data_without_geometry)
    assert len(coords) == 2


def test_path_geometry_produces_more_points_than_the_node_path_when_a_curved_edge_is_crossed(base_graph, bbox):
    u, v, key, data = next(
        (u, v, key, data)
        for u, v, key, data in base_graph.edges(keys=True, data=True)
        if data.get("geometry") is not None
        and len(list(data["geometry"].coords)) > 2
        and len(base_graph[u][v]) == 1
    )
    coords, distance_m, _elevation_gain_m = _path_geometry(base_graph, [u, v])
    assert len(coords) > 2
    assert distance_m == pytest.approx(data.get("length", 0.0))


def test_edge_coords_reverses_geometry_to_match_traversal_direction(base_graph):
    u, v, _key, data = next(
        (u, v, key, data)
        for u, v, key, data in base_graph.edges(keys=True, data=True)
        if data.get("geometry") is not None
    )
    reversed_data = dict(data)
    reversed_data["geometry"] = LineString(list(reversed(list(data["geometry"].coords))))
    coords = _edge_coords(base_graph, u, v, reversed_data)
    assert (coords[0].lat, coords[0].lon) == (base_graph.nodes[u]["y"], base_graph.nodes[u]["x"])
    assert (coords[-1].lat, coords[-1].lon) == (base_graph.nodes[v]["y"], base_graph.nodes[v]["x"])
