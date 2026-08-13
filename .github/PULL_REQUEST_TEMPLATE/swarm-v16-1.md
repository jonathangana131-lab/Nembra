<!-- Nembra Swarm V16.1 managed PR metadata. Keep these stable so the trusted admission gate can converge workers before PR soup forms. -->
SWARM_PROTOCOL: 16.1
SWARM_SCHEMA: 2
SWARM_LANE: <stable-lane-id>
SWARM_SLOT: <stable-blocker-or-work-slot>
SWARM_WORKER: sol-YYYYMMDD-<unique>
SWARM_BRANCH_INTENT: canonical
<!-- Validation/tournament only: SWARM_PARENT_PR: #123 -->
<!-- Tournament only: SWARM_TOURNAMENT_ID: <authorized-id> -->

## Outcome

Describe the coherent result this PR should produce. Do not describe activity as the goal.

## Existing work checked

List the Mission Graph work item, blocker, selected branch/PR, and evidence checked before creating this PR. If equivalent work exists, close this draft and join it instead.

## Acceptance

List exact tests/evidence needed for this head and the integration destination.

## Truth boundary

State what this PR does **not** prove. Simulator/authenticated/physical/command authority remain separate unless explicitly earned.
