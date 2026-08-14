from __future__ import annotations

"""V16.2 CLI binding without duplicating the stable command parser."""

from . import cli as _cli
from . import v16_2 as _v162


def main(argv=None):
    # cli.py intentionally remains the stable command surface. Bind only the
    # V16 policy hooks so older lane/resource commands keep identical behavior.
    _cli.go_cycle = _v162.go_cycle
    _cli.recommend_mission_packets = _v162.recommend_mission_packets
    _cli.v16_graph_service = _v162.v16_graph_service
    _cli.seed_nembra_graph = _v162.seed_nembra_graph
    _cli.role_allocation = _v162.role_allocation
    return _cli.main(argv)
