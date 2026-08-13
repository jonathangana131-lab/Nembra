# Nembra Swarm V16.1 — Convergence Contract

V16.1 is a convergence-policy upgrade over the existing V16 Mission Graph. The stored graph remains schema `16`; V16.1 is activated in place and does not reset missions, evidence, blockers, claims, memory, or physical truth.

## Why V16.1 exists

The first large V16 dogfood proved that Mission Graph improves top-level convergence, but it also exposed a deep-lane failure mode: many workers could still create validation/recovery successors around one blocker faster than integration could consume them. The result was useful evidence mixed with unnecessary branch/PR fanout.

V16.1 moves duplicate suppression earlier. The default action for a worker that discovers equivalent work is now **join**, **review**, **integrate**, or **debug the selected branch** — not create another successor.

## Hard convergence rules

1. **One active builder branch per blocker.** A second builder for the same blocker must join the existing work item/branch.
2. **`allow_duplicate` is not a builder escape hatch.** Builders may duplicate only inside an explicitly authorized solution tournament.
3. **Solution tournaments are capped at two candidates.** A third candidate is rejected.
4. **A blocker gets at most two distinct low-progress attempt branches.** A third low-progress successor is rejected and the blocker family is frozen into convergence mode.
5. **Three low-progress attempts trigger convergence review early.** Workers should consolidate evidence and attack the selected hypothesis rather than create new branch families.
6. **Mission packets explicitly forbid successor PR invention.** Losing a claim means refresh and claim different scheduled work.
7. **New swarm PRs are admitted by GitHub.** Managed PRs must use the V16.1 metadata contract and are rejected when a lane/slot or canonical lane already has an open PR.
8. **No destructive automation.** Admission fails a check and tells the worker where to join; it does not auto-close branches/PRs.

## V16.1 PR metadata

Every new swarm-managed PR must include:

```text
SWARM_PROTOCOL: 16.1
SWARM_SCHEMA: 2
SWARM_LANE: <stable lane id>
SWARM_SLOT: <stable blocker/work slot>
SWARM_WORKER: sol-YYYYMMDD-<unique>
SWARM_BRANCH_INTENT: canonical|validation|review|integration|tournament
```

Validation or tournament PRs must also include:

```text
SWARM_PARENT_PR: #<canonical-or-parent-pr>
```

Tournament PRs additionally require:

```text
SWARM_TOURNAMENT_ID: <authorized tournament id>
```

### Admission behavior

- Same lane + same slot already open → **JOIN_EXISTING**.
- Another canonical PR already open for the lane → **JOIN_CANONICAL**.
- Validation/tournament without a parent → **JOIN_PARENT**.
- More than six open noncanonical PRs in one lane → **CONVERGE_FIRST**.
- Old protocol on a newly created swarm PR → **UPGRADE_METADATA**.

The admission check runs from trusted current `main` through `pull_request_target`; PR-head code is never executed by the write-adjacent control path.

## Branch lifecycle

The first admitted builder work item may use its assigned branch. After that branch exists, all equivalent workers use it. A separate experimental branch requires an authorized two-candidate tournament.

Validation does not automatically deserve a new PR. Prefer, in order:

1. add the validation to the selected branch;
2. review/red-team the existing PR;
3. add a test-only commit on the same branch;
4. use one bounded tournament candidate only when independence is materially required.

When evidence selects a winner, loser branches become superseded and should not continue producing descendants.

## Worker behavior after a lost claim

A lost claim is a routing event, not permission to invent work.

The worker must:

1. refresh Mission Graph and live PR topology;
2. choose another queued/review/integration packet;
3. if no packet remains, review/integrate/debug existing work;
4. idle only if the normal V16 stop gate is satisfied.

## Readiness gate

`Swarm V16.1 Convergence Readiness` must stay green. It compiles the control plane, validates config, runs the retained V16 suite, runs the V16.1 convergence suite, runs neighboring V16 activation/ops/live-refresh regressions, and executes both 30-worker adversarial simulations.

`Swarm V16.1 PR Admission` becomes active on `main` and guards newly opened/reopened/edited swarm PRs.

## Stopwatch metrics for the next swarm

For the next 20+ worker swarm, judge V16.1 using concrete deltas rather than percentages:

- merged product/control-plane PRs;
- blockers actually removed;
- objectives moved to review/integration/DONE;
- duplicate builder branches prevented;
- new PR count versus merged/closed/superseded count;
- distinct branches created for one blocker;
- time from first blocker discovery to selected integrated repair;
- amount of user-visible Nembra work shipped;
- whether the swarm remains stuck in validation/recovery churn.

The target is **more integrated work with fewer PRs**, not maximum agent activity.

## Physical truth boundary

V16.1 does not change the existing truth ladder or physical authority. Simulator evidence is still not physical evidence. Authenticated telemetry is still not automatically physically mapped. Commands still require physical mapping. The scheduler still cannot promote physical GO.
