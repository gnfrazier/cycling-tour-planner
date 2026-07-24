"""Route solving (ctp-core §5.2 `routing/`).

FR10 (multi-waypoint routing) is Leg 3/M5 and is intentionally not
implemented here — `solve_route` takes a single optional destination.
"""

from __future__ import annotations

import uuid

import networkx as nx
import osmnx as ox

from .types import Coord, Graph, Route, RouteShape, Theme

# How far a loop/out-and-back turnaround node's distance-from-start is
# allowed to drift from the requested target (in each direction) while still
# being a candidate — picking the theme-cheapest node within this band, not
# just the single closest-by-length node, is what lets theme actually vary
# the turnaround point (and therefore the route) for these shapes.
_DISTANCE_BAND_TOLERANCE = 0.15


def _nearest_node(graph: Graph, coord: Coord) -> int:
    return ox.distance.nearest_nodes(graph, coord.lon, coord.lat)


def _node_near_distance(graph: Graph, source: int, target_m: float) -> int:
    """Pick a reachable node whose shortest-path distance from source is
    close to target_m — used to synthesize a turnaround/destination when the
    caller gives a target distance instead of an explicit endpoint.

    Distance is measured by raw road length (theme-independent), but among
    the nodes within `_DISTANCE_BAND_TOLERANCE` of the target distance, the
    theme-cheapest one is picked (weight="cost") — so different themes get a
    real chance to end up with different turnaround points, and therefore
    different routes, instead of always converging on the same node."""
    lengths = nx.single_source_dijkstra_path_length(graph, source, weight="length")
    if not lengths:
        raise ValueError("no reachable nodes from the start point")
    band = {n: d for n, d in lengths.items() if abs(d - target_m) <= target_m * _DISTANCE_BAND_TOLERANCE}
    if not band:
        return min(lengths, key=lambda n: abs(lengths[n] - target_m))
    costs = nx.single_source_dijkstra_path_length(graph, source, weight="cost")
    return min(band, key=lambda n: costs.get(n, float("inf")))


def _shortest_path(graph: Graph, source: int, target: int) -> list[int]:
    return nx.shortest_path(graph, source, target, weight="cost")


def _shortest_path_avoiding_edges(
    graph: Graph, source: int, target: int, avoid_pairs: set[frozenset[int]]
) -> list[int] | None:
    """Shortest path with every edge whose (u, v) node pair is in
    avoid_pairs temporarily removed, so a loop's return leg prefers a
    genuinely different street over retracing the outbound one. Returns None
    if no such alternative exists at all (e.g. a true dead-end spur) — the
    caller should then fall back to the unrestricted path, since retracing
    is the only physically correct route there, not a bug."""
    if not avoid_pairs:
        return _shortest_path(graph, source, target)
    removed = [
        (u, v, k, data)
        for u, v, k, data in list(graph.edges(keys=True, data=True))
        if frozenset((u, v)) in avoid_pairs
    ]
    for u, v, k, _data in removed:
        graph.remove_edge(u, v, k)
    try:
        return _shortest_path(graph, source, target)
    except nx.NetworkXNoPath:
        return None
    finally:
        for u, v, k, data in removed:
            graph.add_edge(u, v, k, **data)


def _node_coord(graph: Graph, n: int) -> Coord:
    return Coord(lat=graph.nodes[n]["y"], lon=graph.nodes[n]["x"])


def _sq_dist(a: tuple[float, float], b: tuple[float, float]) -> float:
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2


def _edge_coords(graph: Graph, u: int, v: int, edge_data: dict) -> list[Coord]:
    """Coordinates along one edge, from u to v. Uses the edge's real
    `geometry` LineString when osmnx recorded one (simplified edges between
    intersections keep the original road's curve points), falling back to a
    straight node-to-node chord otherwise — without this, every curve gets
    silently straightened, understating how much distance the curve adds."""
    geom = edge_data.get("geometry")
    if geom is None:
        return [_node_coord(graph, u), _node_coord(graph, v)]
    pts = list(geom.coords)  # [(x, y), ...]
    u_xy = (graph.nodes[u]["x"], graph.nodes[u]["y"])
    if _sq_dist(pts[0], u_xy) > _sq_dist(pts[-1], u_xy):
        pts.reverse()
    return [Coord(lat=y, lon=x) for x, y in pts]


def _path_geometry(graph: Graph, path: list[int]) -> tuple[list[Coord], float, float]:
    """Walks path's edges once, returning (coords, distance_m,
    elevation_gain_m). Distance/elevation still come from each edge's own
    `length`/`elev_gain` attributes; coords follow real road curvature via
    `_edge_coords` instead of just the path's node positions."""
    coords = [_node_coord(graph, path[0])]
    distance_m = 0.0
    elevation_gain_m = 0.0
    for u, v in zip(path, path[1:]):
        edge_data = min(graph[u][v].values(), key=lambda d: d.get("cost", float("inf")))
        distance_m += edge_data.get("length", 0.0)
        elevation_gain_m += edge_data.get("elev_gain", 0.0)
        coords.extend(_edge_coords(graph, u, v, edge_data)[1:])
    return coords, distance_m, elevation_gain_m


def solve_route(
    graph: Graph,
    start: Coord,
    end: Coord | None,
    shape: RouteShape,
    theme: Theme,
    cpus: int,
    target_distance_km: float | None = None,
) -> Route:
    """Solve a themed route over an already-scored graph.

    Weighting is a pipeline stage that runs before this one (`scoring.score_edges`
    must have already annotated every edge's `cost`) — `solve_route` only
    walks the graph the pipeline already scored, rather than re-accepting a
    WeightProfile it would do nothing with.

    `cpus` is accepted per the ctp-core boundary contract (Architecture
    §5.1: the caller decides core allocation, the library never discovers
    it) but a single-solve Dijkstra doesn't parallelize — it's plumbed
    through for forward compatibility with batched/background solving.
    """
    del cpus  # not yet used by a single-solve Dijkstra; see docstring

    start_node = _nearest_node(graph, start)

    if shape is RouteShape.POINT_TO_POINT:
        if end is None:
            raise ValueError("point_to_point requires an end coordinate")
        end_node = _nearest_node(graph, end)
        path = _shortest_path(graph, start_node, end_node)
        coords, distance_m, elevation_gain_m = _path_geometry(graph, path)

    elif shape is RouteShape.OUT_AND_BACK:
        if end is not None:
            turnaround_node = _nearest_node(graph, end)
        elif target_distance_km is not None:
            turnaround_node = _node_near_distance(graph, start_node, target_distance_km * 1000 / 2)
        else:
            raise ValueError("out_and_back requires an end coordinate or a target_distance_km")
        leg_out = _shortest_path(graph, start_node, turnaround_node)
        out_coords, leg_distance_m, leg_elevation_m = _path_geometry(graph, leg_out)
        distance_m = leg_distance_m * 2
        elevation_gain_m = leg_elevation_m * 2
        coords = out_coords + list(reversed(out_coords))[1:]

    elif shape is RouteShape.LOOP:
        if target_distance_km is None:
            raise ValueError("loop requires a target_distance_km")
        turnaround_node = _node_near_distance(graph, start_node, target_distance_km * 1000 / 2)
        leg_out = _shortest_path(graph, start_node, turnaround_node)

        used_pairs = {frozenset((u, v)) for u, v in zip(leg_out, leg_out[1:])}
        leg_back = _shortest_path_avoiding_edges(graph, turnaround_node, start_node, used_pairs)
        if leg_back is None:
            leg_back = _shortest_path(graph, turnaround_node, start_node)

        out_coords, out_distance_m, out_elevation_m = _path_geometry(graph, leg_out)
        back_coords, back_distance_m, back_elevation_m = _path_geometry(graph, leg_back)
        distance_m = out_distance_m + back_distance_m
        elevation_gain_m = out_elevation_m + back_elevation_m
        coords = out_coords + back_coords[1:]

    else:
        raise ValueError(f"unknown route shape: {shape}")

    return Route(
        id=str(uuid.uuid4()),
        theme=theme,
        shape=shape,
        coords=coords,
        distance_m=distance_m,
        elevation_gain_m=elevation_gain_m,
    )
