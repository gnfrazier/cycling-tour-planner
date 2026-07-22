"""Route solving (ctp-core §5.2 `routing/`).

FR10 (multi-waypoint routing) is Leg 3/M5 and is intentionally not
implemented here — `solve_route` takes a single optional destination.
"""

from __future__ import annotations

import uuid

import networkx as nx
import osmnx as ox

from .types import Coord, Graph, Route, RouteShape, Theme

# How much a used edge's cost is inflated on a loop's return leg, so the
# second shortest-path solve tends to pick a different way home instead of
# retracing the outbound leg exactly.
_LOOP_REUSE_PENALTY = 8.0


def _nearest_node(graph: Graph, coord: Coord) -> int:
    return ox.distance.nearest_nodes(graph, coord.lon, coord.lat)


def _node_near_distance(graph: Graph, source: int, target_m: float) -> int:
    """Pick the reachable node whose shortest-path distance from source is
    closest to target_m — used to synthesize a turnaround/destination when
    the caller gives a target distance instead of an explicit endpoint."""
    lengths = nx.single_source_dijkstra_path_length(graph, source, weight="length")
    if not lengths:
        raise ValueError("no reachable nodes from the start point")
    return min(lengths, key=lambda n: abs(lengths[n] - target_m))


def _shortest_path(graph: Graph, source: int, target: int) -> list[int]:
    return nx.shortest_path(graph, source, target, weight="cost")


def _path_coords(graph: Graph, path: list[int]) -> list[Coord]:
    return [Coord(lat=graph.nodes[n]["y"], lon=graph.nodes[n]["x"]) for n in path]


def _path_stats(graph: Graph, path: list[int]) -> tuple[float, float]:
    distance_m = 0.0
    elevation_gain_m = 0.0
    for u, v in zip(path, path[1:]):
        edge_data = min(graph[u][v].values(), key=lambda d: d.get("cost", float("inf")))
        distance_m += edge_data.get("length", 0.0)
        elevation_gain_m += edge_data.get("elev_gain", 0.0)
    return distance_m, elevation_gain_m


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
        distance_m, elevation_gain_m = _path_stats(graph, path)
        coords = _path_coords(graph, path)

    elif shape is RouteShape.OUT_AND_BACK:
        if end is not None:
            turnaround_node = _nearest_node(graph, end)
        elif target_distance_km is not None:
            turnaround_node = _node_near_distance(graph, start_node, target_distance_km * 1000 / 2)
        else:
            raise ValueError("out_and_back requires an end coordinate or a target_distance_km")
        leg_out = _shortest_path(graph, start_node, turnaround_node)
        leg_distance_m, leg_elevation_m = _path_stats(graph, leg_out)
        distance_m = leg_distance_m * 2
        elevation_gain_m = leg_elevation_m * 2
        coords = _path_coords(graph, leg_out) + _path_coords(graph, list(reversed(leg_out))[1:])

    elif shape is RouteShape.LOOP:
        if target_distance_km is None:
            raise ValueError("loop requires a target_distance_km")
        turnaround_node = _node_near_distance(graph, start_node, target_distance_km * 1000 / 2)
        leg_out = _shortest_path(graph, start_node, turnaround_node)

        used_edges: list[tuple[int, int, int, float]] = []
        for u, v in zip(leg_out, leg_out[1:]):
            key, edge_data = min(graph[u][v].items(), key=lambda kv: kv[1].get("cost", float("inf")))
            used_edges.append((u, v, key, edge_data["cost"]))
            edge_data["cost"] *= _LOOP_REUSE_PENALTY
        try:
            leg_back = _shortest_path(graph, turnaround_node, start_node)
        finally:
            for u, v, key, original_cost in used_edges:
                graph[u][v][key]["cost"] = original_cost

        out_distance_m, out_elevation_m = _path_stats(graph, leg_out)
        back_distance_m, back_elevation_m = _path_stats(graph, leg_back)
        distance_m = out_distance_m + back_distance_m
        elevation_gain_m = out_elevation_m + back_elevation_m
        coords = _path_coords(graph, leg_out) + _path_coords(graph, leg_back)[1:]

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
