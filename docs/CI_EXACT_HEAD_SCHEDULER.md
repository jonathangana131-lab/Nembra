# Scheduled Xcode 27 exact-head PR gate

Date: 2026-08-06
Worker: `chat-f2k7q`

## Purpose

Nembra's v5 swarm needs exact-final-head Xcode 27 / iPhone 12 / iOS 27 Simulator proof before accepting substantial software lanes.

Current connected GitHub mutations do not reliably emit Actions webhook events in this runtime. Two live experiments established that boundary:

1. an owner-authored `/xcode27` issue comment created through the ChatGPT Codex GitHub App was recorded by GitHub while the workflow was active on the default branch, but no `issue_comment` workflow run appeared;
2. a same-repository non-draft PR opened through the connector after `pull_request.opened` support was already on the default branch likewise produced no workflow run.

Those failures are preserved in `docs/CI_EXACT_HEAD_GATE_EVIDENCE.md` on PR #42. This scheduler is the fallback that does **not** depend on connector-created repository mutations emitting an Actions event.

## Trigger contract

`.github/workflows/xcode27-pr-scheduler.yml` runs from the repository's default branch on:

- a five-minute UTC schedule offset away from minute zero: `4-59/5 * * * *`;
- optional human `workflow_dispatch`.

GitHub documents five minutes as the shortest scheduled-workflow interval and warns that scheduled runs may be delayed during periods of high load, especially near the start of an hour. Therefore the scheduler is a best-effort acceptance queue, not a real-time timer or reconnect mechanism.

A delayed scheduled run does not change software truth. The resolver always reads current repository/PR state when the scheduled run actually starts.

## Eligible PRs

Every pass reads the repository's current `default_branch` through the GitHub API, then scans open pull requests.

A PR is eligible only when all of these are true:

- it is open;
- it is not draft;
- its base is the repository's current default branch;
- its head repository is exactly `jonathangana131-lab/Nembra`;
- its head ref begins with `parallel/`;
- comparing current default branch to the exact head reports `behind_by == 0`;
- its exact head SHA does not already have a completed `Nembra/Xcode27 Exact Head` status;
- its exact head SHA does not have a non-stale pending status in that context.

The `behind_by == 0` gate is important: v5 requires a lane to refresh/reconcile current main before final acceptance. Running the expensive Xcode gate on a head that is already behind main would at best be diagnostic, because reconciliation would create a new SHA and require another exact-head run. The scheduler therefore refuses that known-stale acceptance work instead of spending the self-hosted runner on it.

A draft PR is a cheap work/checkpoint state. A worker makes a coherent lane schedulable only after focused validation, overlap checks, and required fresh-main reconciliation.

This scheduler does not touch or mutate another worker's branch. It reads repository/PR state, selects a candidate, and publishes commit status for that immutable SHA.

## Exact-head status context

The durable status context is:

`Nembra/Xcode27 Exact Head`

The exact commit SHA is the identity of a gate result.

Status meanings:

- no status: eligible when the PR is otherwise ready/current;
- `pending`: currently queued/running; skipped for two hours to prevent duplicate expensive gates;
- stale `pending` older than two hours: eligible for recovery;
- `success`: this exact SHA completed the scheduled Simulator gate successfully;
- `failure`: this exact SHA ran and failed the gate; the unchanged SHA is not automatically retried every five minutes;
- `error`: the exact SHA's gate was cancelled/errored; the unchanged SHA is not automatically retried every five minutes.

If a worker fixes a failure or reconciles newer main, the new commit SHA has no completed status and becomes eligible again after it is ready/current. This preserves exact-head semantics without retry storms.

A worker or coordinator may intentionally create a new commit/reconciliation head after diagnosing a failed gate. Blind reruns of the same broken software are not the scheduler's default behavior.

## Candidate selection

One scheduled pass selects at most one PR.

Default order is oldest PR update first so a busy swarm drains rather than starving older acceptance-ready lanes.

A PR may add this exact body marker when there is a real dependency/unblocking reason:

`XCODE27_SCHEDULE_PRIORITY: true`

Priority PRs are considered before normal PRs, then oldest update wins within the same priority class.

The marker does not bypass fresh-main ancestry, security, readiness, exact-head, or status rules.

## Concurrency

The workflow uses one repository-wide scheduler concurrency group with `cancel-in-progress: false`.

The intent is:

- at most one scheduler/Xcode gate actively consumes the self-hosted runner from this workflow;
- repeated five-minute ticks do not create many simultaneous self-hosted jobs;
- after the active run finishes, a surviving pending scheduler run reevaluates current PR/status state and can select the next eligible exact head.

GitHub concurrency may keep only a bounded pending set and may replace an older pending run with a newer pending run. That is acceptable because each scheduler run performs fresh selection; schedule ticks are not durable work items themselves. The durable work item is the PR head plus its exact commit status.

## Security boundary

The self-hosted `xcode-27` runner must never execute arbitrary fork code.

The scheduler fails closed by requiring before the Xcode job:

- same repository head (`pr.head.repo.full_name` exactly equals Nembra);
- `parallel/**` worker/recovery/integration branch shape;
- non-draft state;
- default-branch target;
- current-main ancestry (`behind_by == 0`);
- immutable resolved commit SHA.

The resolver runs on GitHub-hosted `ubuntu-latest` and checks out no PR code.

The pending/final status publisher jobs also run on GitHub-hosted runners. Only those jobs receive `statuses: write`; they do not check out PR code.

The Xcode job inherits read-only repository permissions. It checks out the frozen SHA directly, prints the expected PR/head/SHA and actual `git rev-parse HEAD`, and fails if they differ.

A fork, feature branch outside `parallel/**`, draft lane, or branch already behind current main cannot reach the self-hosted runner through this scheduler.

## Gate contents

For the selected immutable SHA the Xcode job performs the same core acceptance work as the established Simulator workflow:

1. checkout exact SHA;
2. assert checkout SHA equality;
3. `plutil -lint Nembra.xcodeproj/project.pbxproj`;
4. `scripts/validate_pbxproj_references.py`;
5. shell syntax check for `scripts/ci/xcode27_simulator_capture.sh`;
6. `swift test` in `Packages/NembraCore`;
7. `scripts/ci/xcode27_simulator_capture.sh` on the `xcode-27` runner;
8. upload Simulator screenshots/log artifacts even when the gate fails;
9. publish final success/failure/error status to the exact SHA.

A green status is only software evidence for that commit. It is never physical AOVOPRO ES80 proof.

## Worker protocol

For a substantial lane that requires the full gate:

1. keep the PR draft during implementation/checkpoints;
2. run focused package/unit/static checks first;
3. refresh main and active overlap;
4. reconcile if required so current main is an ancestor (`behind_by == 0`);
5. update the V5 recovery capsule with the exact candidate head;
6. mark the PR ready;
7. let the scheduler attach `Nembra/Xcode27 Exact Head` to that exact SHA;
8. inspect the run, logs, and artifacts rather than treating status alone as sufficient diagnosis;
9. if the gate fails, fix the diagnosed issue on a new head;
10. if main/parent changes and the lane reconciles, the new SHA requires a new exact-head gate;
11. refresh main once more immediately before merge; if it advanced, reconcile and gate the new SHA again;
12. merge only when the final unchanged/current head satisfies the lane's required acceptance evidence.

Workers should not add meaningless commits merely to manufacture another gate. A new SHA should represent a real fix, reconciliation, or evidence update.

## Live validation target

PR #42 (`ci-exact-head-gate-evidence`, worker `chat-f2k7q`) is the controlled evidence lane for proving scheduler behavior end to end.

Other higher-value coordinator PRs may also carry `XCODE27_SCHEDULE_PRIORITY: true`. The scheduler should choose whichever priority candidate is **both current with main and oldest updated**; the evidence lane does not override dependency-unblocking work merely to make the test easier.

After this fresh-main eligibility hardening reaches default, PR #42 will be reconciled onto the exact new main and kept ready with its priority marker. The expected proof is:

- resolver selects an exact eligible current SHA;
- pending status appears in `Nembra/Xcode27 Exact Head`;
- immutable checkout log shows expected == actual SHA;
- project/package/Simulator steps complete or produce a diagnosable real failure;
- artifact upload is inspectable;
- final status targets the same SHA and scheduler run.

If PR #42's run succeeds, its evidence document will be updated with the real run ID/results. That update changes its SHA, so it must be reconciled/current and receive another exact-head scheduled gate before PR #42 itself can merge.

## Relationship to other CI

This scheduler is supplemental.

- `.github/workflows/xcode27-simulator.yml` remains the normal main/feature/manual QA path.
- `.github/workflows/xcode27-pr-command.yml` preserves event-driven/human command support where GitHub actually emits those events.
- PR #13 separately owns a `parallel/**` push-trigger change to the normal workflow; this scheduler does not modify that file.

If a reliable direct workflow-dispatch capability later becomes available to the connected worker environment, the schedule may be reduced or retired deliberately after no active lane depends on it.

## Hardware truth boundary

Nothing in this infrastructure verifies:

- real ES80 advertisement/GATT/DP semantics;
- battery source/scale/cadence;
- motorized commands or acknowledgements;
- physical background reconnect;
- outdoor GPS behavior;
- physical iPhone 12 thermal/energy behavior.

Those remain separate physical evidence requirements. Simulator success must never be promoted into hardware truth.
