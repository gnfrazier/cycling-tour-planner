from ctp_core.graph import build_graph
from ctp_core.types import BBox


def test_build_graph_returns_simplified_populated_graph(tmp_path):
    bbox = BBox(west=-82.030, south=35.675, east=-82.000, north=35.700)
    graph = build_graph(bbox, "bike", tmp_path)

    assert graph.number_of_nodes() > 0
    assert graph.number_of_edges() > 0
    assert graph.graph.get("simplified") is True

    _node_id, data = next(iter(graph.nodes(data=True)))
    assert "y" in data and "x" in data  # lat/lon present


def test_build_graph_uses_its_own_cache_dir(tmp_path):
    bbox = BBox(west=-82.030, south=35.675, east=-82.000, north=35.700)
    build_graph(bbox, "bike", tmp_path)
    assert any(tmp_path.iterdir())
