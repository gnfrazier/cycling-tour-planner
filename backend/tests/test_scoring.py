import pytest

from ctp_core.scoring import THEME_PROFILES, WeightSchedule, score_edges
from ctp_core.types import Theme


def test_every_theme_has_a_weight_profile():
    assert set(THEME_PROFILES) == set(Theme)


def test_weight_schedule_is_constant_at_any_position():
    schedule = WeightSchedule(THEME_PROFILES[Theme.FLATTEST])
    assert schedule.at(0.0) == schedule.at(100.0) == schedule.at(-5.0)


def test_score_edges_assigns_a_positive_cost_to_every_edge(base_graph, bbox):
    graph = score_edges(base_graph.copy(), WeightSchedule(THEME_PROFILES[Theme.LOWEST_TRAFFIC]), bbox=bbox)
    assert graph.number_of_edges() > 0
    for _u, _v, _key, data in graph.edges(keys=True, data=True):
        assert data["cost"] > 0


def test_flattest_and_most_climbing_diverge_on_a_hilly_edge(base_graph, bbox):
    hilly = next(
        ((u, v, k) for u, v, k, d in base_graph.edges(keys=True, data=True) if d.get("elev_gain", 0) > 2),
        None,
    )
    if hilly is None:
        pytest.skip("no sufficiently hilly edge in the test bbox to distinguish themes")
    u, v, k = hilly

    flat_graph = score_edges(base_graph.copy(), WeightSchedule(THEME_PROFILES[Theme.FLATTEST]), bbox=bbox)
    climb_graph = score_edges(base_graph.copy(), WeightSchedule(THEME_PROFILES[Theme.MOST_CLIMBING]), bbox=bbox)

    assert flat_graph[u][v][k]["cost"] > climb_graph[u][v][k]["cost"]
