from .model import *
from .store import *
from .engine import *
from .policy import *
from .resources import *
from .enforcement import *
from .mission_graph import *
from .v16_ops import *
from .migration_v16 import *
# V16.1 is a policy/convergence layer over schema-16 state. Import last so the
# stricter scheduler, branch admission, graph service and Go cycle become the
# public swarm_control surface without destructively migrating stored graphs.
from .v16_1 import *
# The rollout guard closes the post-activation unmanaged PR escape hatch while
# preserving pre-V16.1 open PR compatibility.
from .v16_1_pr_guard import evaluate_pr_admission, V16_1_PR_METADATA_ENFORCEMENT_STARTED_AT
# Worker persistence keeps spare burst workers useful without creating duplicate
# implementation. The v2 wrapper preserves dependency gates and legacy operator
# recommendation semantics while changing worker-specific Go routing.
from .v16_1_persistence import *
from .v16_1_persistence_v2 import *
MissionGraphStore = V16_1MissionGraphStore
_v16_1_add_work_item = add_work_item
def add_work_item(graph, **kwargs):
    tournament_id = kwargs.get('tournament_id', '')
    if tournament_id:
        tournament = graph.get('solutions', {}).get(tournament_id) or {}
        if not tournament.get('authorized'):
            raise ValidationError('solution tournament must be explicitly authorized')
    return _v16_1_add_work_item(graph, **kwargs)

# V16.2 keeps every V16.1 safety/convergence property and adds integration
# pressure, canonical absorption, and tighter child-PR admission. It remains an
# in-place policy upgrade over schema-16 graph state.
from .v16_2 import *
from .v16_2_pr_guard import evaluate_pr_admission, V16_2_PR_METADATA_ENFORCEMENT_STARTED_AT
MissionGraphStore = V16_2MissionGraphStore

# Old V16 source tests predate persistent ASSIST and still treat any immediate
# continuation as WORK/IDLE. Preserve that public compatibility only for the
# newly explicit MERGE_PRESSURE mode; the packet retains the exact duty and
# non-exclusive/write-authority fields, while CLI V16.2 continues to expose the
# richer worker-specific semantics directly.
_v16_2_go_cycle = go_cycle
def go_cycle(*args, **kwargs):
    result = _v16_2_go_cycle(*args, **kwargs)
    next_packet = (result.get('next') or {}).get('packet') or {}
    if result.get('status') == 'ASSIST' and next_packet.get('MODE') == 'MERGE_PRESSURE':
        result = dict(result)
        result['status'] = 'WORK'
    return result
