from __future__ import annotations

from copy import deepcopy
from typing import Any, Mapping

from .mission_graph import migrate_legacy_lane as _migrate_legacy_lane
from .model import ValidationError


def normalize_legacy_priority(value: Any) -> int:
    """Map historical V13/V14/V15 priority encodings into V16's 0..9 scale."""
    if isinstance(value, bool):
        raise ValidationError('legacy priority cannot be boolean')
    if isinstance(value, int):
        if 0 <= value <= 9:
            return value
        raise ValidationError('legacy numeric priority outside 0..9')
    if isinstance(value, str):
        text=value.strip().upper()
        if text.isdigit():
            number=int(text)
            if 0 <= number <= 9:
                return number
        severity={'P0':0,'P1':1,'P2':2,'P3':3}
        if text in severity:
            return severity[text]
        named={'CRITICAL':0,'HIGHEST':0,'URGENT':0,'HIGH':2,'MEDIUM':5,'NORMAL':5,'LOW':7,'BACKGROUND':9}
        if text in named:
            return named[text]
    raise ValidationError(f'unsupported legacy priority {value!r}')


def normalize_legacy_lane(lane: Mapping[str,Any]) -> dict[str,Any]:
    normalized=deepcopy(dict(lane))
    normalized['priority']=normalize_legacy_priority(normalized.get('priority',5))
    return normalized


def migrate_legacy_lane(graph: dict[str,Any], lane: Mapping[str,Any], now=None) -> dict[str,Any]:
    """Backward-compatible V16 migration wrapper for heterogeneous legacy state."""
    return _migrate_legacy_lane(graph,normalize_legacy_lane(lane),now=now)
