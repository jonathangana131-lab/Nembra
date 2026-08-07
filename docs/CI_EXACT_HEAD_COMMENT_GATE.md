# Exact-head Xcode 27 PR gate

Updated: 2026-08-06

## Purpose

Nembra needs Xcode 27 / iPhone 12 Simulator acceptance tied to an immutable pull-request head, without allowing fork code onto the self-hosted `xcode-27` runner or silently treating stale CI as proof for a newer commit.

`.github/workflows/xcode27-pr-command.yml` supports two request families:

- automatic acceptance requests from same-repository non-draft PR lifecycle events;
- an explicit trusted `/xcode27` PR conversation command.

The workflow resolves the current PR on a GitHub-hosted runner before any PR code can reach `xcode-27`.

## Automatic acceptance usage

The workflow listens to these `pull_request` activity types:

- `opened`;
- `synchronize`;
- `reopened`;
- `ready_for_review`.

The intended worker rhythm is:

1. keep implementation/checkpoint PRs draft while they are moving;
2. perform focused/static/package validation first;
3. refresh `main`, ownership, dependencies, and overlap;
4. mark a coherent same-repository PR ready for review;
5. let the exact-head gate exercise that current acceptance candidate;
6. if the PR changes while it remains ready, a current `synchronize` event may supersede the older valid gate for that PR;
7. merge only when the required successful run corresponds to the final unchanged acceptance head.

Draft PR checkpoint churn does not intentionally consume the self-hosted acceptance gate.

## Delayed pull-request event freshness guard

A `pull_request` webhook payload is evidence about the event that GitHub emitted. It is **not** automatically current PR truth when delivery is delayed or processed out of order.

This mattered during the 2026-08-06 GitHub Actions incident. PR #50 provided a concrete sequence:

- run `31129569763` resolved delayed event head `bfabe8e7...` after the live PR had already advanced; its Xcode job was later cancelled;
- run `31130118936` resolved later-but-still-stale event head `a9db1a09...` after another PR advance and also ended cancelled;
- a later run finally targeted the then-current `3cb6e7ad...` head.

The resolver therefore live-fetches the PR through the GitHub API for every accepted trigger.

For an automatic `pull_request` event, the self-hosted job is allowed only when all of these remain true at resolver time:

- the live PR is open;
- the live PR is not draft;
- the live head repository is Nembra itself;
- the event payload `head.sha` exactly equals the live PR's current `head.sha`.

If the payload head is stale, the resolver records a notice and returns `should_run=false`. The self-hosted Simulator job never starts for that stale event.

This guard is intentionally before the per-PR Simulator concurrency group. A delayed obsolete event therefore cannot enter the Xcode job merely because it was valid when GitHub originally emitted it.

The guard does **not** claim a PR can never change after resolver time. The resolver freezes one immutable SHA. Workers still compare the completed run SHA with the final PR SHA immediately before acceptance/merge; any later head change invalidates older proof.

## Optional trusted `/xcode27` command

On a Nembra pull request, an owner/member/collaborator may add this exact PR conversation comment:

```text
/xcode27
```

The workflow-level filter requires the exact body and trusted GitHub author association.

The resolver then live-fetches the PR and freezes its **current** head. This manual path deliberately remains distinct from automatic ready-PR gating: it does not inherit the automatic event's non-draft freshness rule merely because both paths share the same Xcode job.

The same-repository check still applies before self-hosted execution, so a fork head cannot reach `xcode-27` through the command path.

Historical note: early during the 2026-08-06 Actions incident, connector-created comments appeared to produce no run at the immediate observation point. Later backlog recovery showed delayed `issue_comment` workflow delivery. That incident evidence should not be generalized into a permanent claim that connector-created comments never trigger Actions.

## Exact-head behavior

For a valid request the workflow:

1. live-fetches the PR;
2. verifies the current head repository equals Nembra;
3. for automatic PR events, rejects stale payload heads or a live draft/closed PR before self-hosted execution;
4. freezes the live current `head.sha`;
5. checks out that immutable SHA on `xcode-27`;
6. prints expected and actual `git rev-parse HEAD`;
7. fails if those SHAs differ;
8. validates the Xcode project and reference graph;
9. runs NembraCore tests;
10. runs the Xcode 27 / iPhone 12 Simulator build-test-capture script;
11. uploads Simulator screenshots/log artifacts even on a later gate failure.

A successful run proves only the exact software commit it exercised.

## Security boundary

The self-hosted runner must never execute arbitrary fork code.

The workflow therefore keeps these boundaries:

- resolver executes on GitHub-hosted `ubuntu-latest` and checks out no PR code;
- workflow token permissions remain read-only (`contents: read`, `pull-requests: read`);
- live head repository must equal `jonathangana131-lab/Nembra`;
- fork heads fail closed before the Xcode job;
- checkout uses the resolved immutable SHA, never a mutable branch name;
- trusted command filtering occurs before resolver execution;
- automatic events additionally require live open/non-draft state plus payload-head/live-head equality.

## Concurrency

Simulator concurrency remains scoped by resolved PR number:

`nembra-xcode27-pr-command-<PR_NUMBER>`

with `cancel-in-progress: true`.

That remains intentional after the stale-event guard:

- a newer **valid** gate for the same PR may supersede its older valid in-progress gate;
- a stale automatic event is filtered before it enters the Simulator job and therefore cannot cancel via that group;
- unrelated PRs do not cancel each other.

Changing the concurrency key to SHA would preserve stale work rather than enforcing the desired "newer valid acceptance candidate wins" contract, so the stale-event fix is deliberately implemented in resolver freshness rather than by weakening per-PR cancellation.

## Relationship to the scheduled fallback

`.github/workflows/xcode27-pr-scheduler.yml` is a separate supplemental path for ready `parallel/**` PRs. It live-selects current eligible heads and publishes exact-SHA commit status.

The command/PR-event gate and scheduler should not be treated as competing truth systems. In every path, the acceptance identity is the immutable commit SHA actually exercised.

## Truth / acceptance boundary

This CI infrastructure does not verify:

- physical AOVOPRO ES80 Bluetooth/GATT/DP behavior;
- battery source/scaling/cadence;
- motorized command semantics or acknowledgements;
- real outdoor GPS behavior;
- physical background reconnect behavior;
- physical iPhone 12 thermal/energy/performance behavior unless separate device evidence explicitly supplies it.

Workers remain responsible for current dependency/ownership checks, artifact inspection where required, final-head comparison, and expected-head merge protection.
