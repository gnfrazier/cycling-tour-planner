import pytest

from ctp_core.scoring import THEME_PROFILES, WeightSchedule, _surface_class, score_edges
from ctp_core.types import Theme, WeightProfile


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


# FR12 -- surface scoring


@pytest.mark.parametrize(
    "surface,expected_class",
    [
        ("asphalt", 4),
        ("concrete", 4),
        ("paving_stones", 3),
        ("compacted", 2),
        ("gravel", 1),
        ("dirt", 0),
        ("sand", 0),
        (None, 2),  # unknown/missing -- middling, not worst-case, same as _highway_class
        ("some_unlisted_surface", 2),
    ],
)
def test_surface_class_maps_osm_surface_tags(surface, expected_class):
    edge_data = {"surface": surface} if surface is not None else {}
    assert _surface_class(edge_data) == expected_class


def test_surface_class_takes_the_first_value_of_a_list_tag():
    assert _surface_class({"surface": ["gravel", "dirt"]}) == 1


def test_surface_preference_diverges_paved_from_unpaved_on_an_unpaved_edge(base_graph, bbox):
    unpaved = next(
        (
            (u, v, k)
            for u, v, k, d in base_graph.edges(keys=True, data=True)
            if _surface_class(d) < 2
        ),
        None,
    )
    if unpaved is None:
        pytest.skip("no unpaved-tagged edge in the test bbox to distinguish surface preference")
    u, v, k = unpaved

    prefer_paved = score_edges(base_graph.copy(), WeightSchedule(WeightProfile(surface_preference=1.0)), bbox=bbox)
    prefer_unpaved = score_edges(base_graph.copy(), WeightSchedule(WeightProfile(surface_preference=-1.0)), bbox=bbox)

    assert prefer_paved[u][v][k]["cost"] > prefer_unpaved[u][v][k]["cost"]


# FR13 -- real WeightSchedule position resolution


def test_weight_schedule_has_overrides_reflects_construction():
    assert not WeightSchedule(WeightProfile()).has_overrides
    assert WeightSchedule(WeightProfile(), [(0.0, 10.0, WeightProfile(elevation_gain=1.0))]).has_overrides


def test_weight_schedule_resolves_overrides_by_position():
    default = WeightProfile(elevation_gain=-1.0)
    day1 = WeightProfile(elevation_gain=1.0)
    day2 = WeightProfile(surface_preference=-1.0)
    schedule = WeightSchedule(default, [(0.0, 10.0, day1), (10.0, 20.0, day2)])

    assert schedule.at(5.0) == day1
    assert schedule.at(15.0) == day2
    assert schedule.at(25.0) == default  # past every override -- falls back to the tour default


def test_weight_schedule_first_matching_override_wins_on_overlap():
    default = WeightProfile()
    first = WeightProfile(elevation_gain=1.0)
    second = WeightProfile(elevation_gain=-1.0)
    schedule = WeightSchedule(default, [(0.0, 10.0, first), (5.0, 15.0, second)])

    assert schedule.at(7.0) == first


def test_score_edges_positions_km_selects_override_profile_per_edge(base_graph, bbox):
    # Force every edge's estimated position past the override's range, and
    # confirm those edges fall back to the default profile rather than the
    # override -- i.e. positions_km, not just override presence, drives at().
    default = WeightProfile(elevation_gain=-1.0)
    override_profile = WeightProfile(elevation_gain=1.0)
    schedule = WeightSchedule(default, [(0.0, 0.001, override_profile)])  # a near-zero-width window

    far_positions = {n: 1000.0 for n in base_graph.nodes}
    graph = score_edges(base_graph.copy(), schedule, bbox=bbox, positions_km=far_positions)
    baseline = score_edges(base_graph.copy(), WeightSchedule(default), bbox=bbox)

    for u, v, k in list(graph.edges(keys=True))[:5]:
        assert graph[u][v][k]["cost"] == pytest.approx(baseline[u][v][k]["cost"])
