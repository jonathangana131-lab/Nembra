# Swarm Foundry 17 congestion control

Foundry 17 preserves Nembra V16.1 claims, evidence, merge train, physical-safety boundaries, and Mission Graph authority while adding repository-level admission and recoverable retirement.

## Why it is active

The 2026-08-14 audit found 300 open PRs while only PR #3142 remained selected by the live Mission Graph. Per-blocker duplicate suppression worked, but repository-wide generations overwhelmed review and integration. Foundry therefore treats incoming chats as optional capacity, not an automatic writer quota.

## Admission law

- Chat capacity ceiling: 20 for the normal ChatGPT Project burst.
- Primary builders: at most 6 project-wide and 2 per Epic, then reduced by ready work.
- Open product PR ceiling: 18.
- Open branch ceiling: 24 active non-protected product branches.
- Review backlog >= 4 throttles new builders to at most 2.
- Integration backlog >= 3 throttles new builders to at most 1.
- Exhausted PR or branch headroom admits no new product builder.
- Red `main` may receive one emergency repair despite congestion.
- Integration, review, verification, evidence transfer, and bounded retirement receive priority.
- Unneeded chats are parked; they do not invent branches.

`scripts/swarmcp/foundry_v17.py` computes this gate and grants no branch authority. A successful atomic V16.1 claim remains mandatory.

## Recoverable reset

The activation reset closes open PRs not selected by the live Mission Graph, labels them `swarm-foundry-retired`, and leaves every branch/commit/PR discussion recoverable. Selected PRs are labelled `swarm-foundry-keep`. No branches are deleted during activation.

Reopening retired work requires a current Mission Graph selection, a non-duplicate work item, fresh claim, exact-head evidence, and repository headroom.

## Physical boundary

Physical NO-GO, signing, device, Bluetooth, and command-verification rules are unchanged. Congestion pressure, cleanup, CI, or chat persistence cannot mint physical authority.

## Validation

```sh
python3 scripts/ci/tests/test_swarm_foundry_v17.py
```

The audited-pressure test proves that a 30-chat arrival under the pre-reset pressure produces zero new primary builders and routes bounded capacity to retirement/review/integration.
