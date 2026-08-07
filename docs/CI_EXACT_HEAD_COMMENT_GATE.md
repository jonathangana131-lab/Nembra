# Exact-head Xcode 27 PR gate

Updated: 2026-08-06

## Purpose

Nembra needs Xcode 27 / iPhone 12 Simulator acceptance tied to an immutable pull-request head, without allowing fork-controlled workflow code or fork PR code onto the self-hosted `xcode-27` runner and without silently treating stale CI as proof for a newer commit.

`.github/workflows/xcode27-pr-command.yml` supports two request families:

- automatic acceptance requests from same-repository non-draft PR lifecycle events, admitted by a **trusted default-branch workflow**;
- an explicit trusted `/xcode27` PR conversation command.

The workflow resolves the current PR on a GitHub-hosted runner before any PR code can reach `xcode-27`.

## Why automatic admission uses `pull_request_target`

This repository is public and the acceptance job uses a self-hosted runner.

GitHub documents an important trust difference:

- `pull_request` runs workflow bytes from the PR merge commit, so a fork controls the workflow definition that GitHub is evaluating;
- `pull_request_target` runs workflow bytes from the base repository's default branch.

A same-repository check written **inside a fork-controlled `pull_request` workflow is not a sufficient self-hosted admission boundary**, because a malicious fork can propose changing or deleting that check before the job is admitted.

Nembra therefore uses `pull_request_target` for automatic PR admission so the resolver and `runs-on: xcode-27` decision originate from trusted default-branch workflow bytes.

`pull_request_target` is a privileged event and must be treated accordingly. This workflow keeps explicit read-only token permissions and executes no PR code on the hosted resolver. It does **not** check out a fork head. The self-hosted checkout is reachable only after the trusted resolver verifies the live head repository is exactly `jonathangana131-lab/Nembra`.

GitHub also warns generally against exposing self-hosted runners to public-repository fork code. Runner-group workflow restrictions/ephemeral isolation remain valuable defense in depth, but the repository workflow must fail closed even when those external settings are unknown.

Reference guidance:

- GitHub Docs: `Securely using pull_request_target`;
- GitHub Docs: `Secure use reference`;
- GitHub Docs: `Managing access to self-hosted runners using groups`.

## Automatic acceptance usage

The trusted workflow listens to these `pull_request_target` activity types:

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
7. merge only when the required successful Simulator job corresponds to the final unchanged acceptance head.

Draft PR checkpoint churn does not intentionally consume the self-hosted acceptance gate.

## Delayed PR-event freshness guard

A `pull_request_target` webhook payload is evidence about the event GitHub emitted. It is **not** automatically current PR truth when delivery is delayed or processed out of order.

This mattered during the 2026-08-06 GitHub Actions incident. PR #50 provided a concrete pre-fix sequence under the older `pull_request` trigger:

- run `31129569763` resolved delayed event head `bfabe8e7...` after the live PR had already advanced; its Xcode job was later cancelled;
- run `31130118936` resolved later-but-still-stale event head `a9db1a09...` after another PR advance and also ended cancelled;
- a later run finally targeted the then-current `3cb6e7ad...` head.

Decoded resolver logs from run `31129569763` show the pre-fix automatic path directly assigned `context.payload.pull_request` and output its head SHA without live-fetching the PR.

The resolver now live-fetches the PR through the GitHub API for every accepted trigger.

For an automatic `pull_request_target` event, the self-hosted job is allowed only when all of these remain true at resolver time:

- the live PR is open;
- the live PR is not draft;
- the live head repository is Nembra itself;
- the event payload `head.sha` exactly equals the live PR's current `head.sha`.

If the payload head is stale, the resolver records a notice and returns `should_run=false`. The self-hosted Simulator job never starts for that stale event.

This guard is intentionally before the per-PR Simulator concurrency group. A delayed obsolete event therefore cannot enter the Xcode job merely because it was valid when GitHub originally emitted it.

The guard does **not** claim a PR can never change after resolver time. The resolver freezes one immutable SHA. Workers still compare the completed Simulator job SHA with the final PR SHA immediately before acceptance/merge; any later head change invalidates older proof.

## Filtered workflow success is not acceptance

GitHub reports a job skipped by a job-level `if` as successful/skipped rather than as a failing required check. Therefore an intentionally filtered stale/draft/closed/fork event may leave the overall workflow run with a successful conclusion even though no PR software ran on `xcode-27`.

**Overall workflow conclusion is not the acceptance signal.**

Exact-head acceptance requires all of the following:

- the `Build, test, and capture exact PR head` (`simulator-qa`) job actually ran;
- that Simulator job concluded `success`, not `skipped`, `cancelled`, or absent;
- its immutable checkout/verification exercised the candidate PR SHA;
- the candidate SHA is still the unchanged final PR head at acceptance time;
- required logs/artifacts were produced and inspected according to the lane's acceptance needs.

A resolver-only success or a workflow run whose Simulator job was filtered is **diagnostic/non-acceptance evidence**, even if GitHub renders the workflow run itself green.

Automation that gates merges must inspect the Simulator job/exact-head evidence, not only the top-level workflow conclusion.

## Bootstrap/backlog caveat

Workflow changes do not retroactively rewrite already-created workflow runs. A delayed event associated with a pre-fix workflow version can still execute that older resolver after this change reaches `main`.

During rollout, old backlog events must therefore be classified by their actual resolver workflow bytes/logs or equivalent run/ref evidence. A pre-fix delayed event that still trusts `context.payload.pull_request` is historical backlog, not evidence that the new default-branch guard regressed.

Post-bootstrap stale-event proof must show the trusted resolver version containing the live PR fetch and freshness check before drawing conclusions about the new guard.

## Optional trusted `/xcode27` command

On a Nembra pull request, an owner/member/collaborator may add this exact PR conversation comment:

```text
/xcode27
```

The workflow-level filter requires the exact body and trusted GitHub author association. `issue_comment` evaluates the workflow definition from the default branch, so this admission path does not trust PR-proposed workflow bytes.

The resolver then live-fetches the PR and freezes its **current** head. This manual path deliberately remains distinct from automatic ready-PR gating: it does not inherit the automatic event's non-draft freshness rule merely because both paths share the same Xcode job.

The same-repository check still applies before self-hosted execution, so a fork head cannot reach `xcode-27` through the command path.

Historical note: early during the 2026-08-06 Actions incident, connector-created comments appeared to produce no run at the immediate observation point. Later backlog recovery showed delayed `issue_comment` workflow delivery. That incident evidence should not be generalized into a permanent claim that connector-created comments never trigger Actions.

## Exact-head behavior

For a valid request the trusted workflow:

1. live-fetches the PR on GitHub-hosted `ubuntu-latest`;
2. verifies the current head repository equals Nembra;
3. for automatic PR events, rejects stale payload heads or a live draft/closed PR before self-hosted execution;
4. freezes the live current `head.sha`;
5. allows the Xcode job only when `same_repo=true` and `should_run=true`;
6. checks out that immutable same-repository SHA on `xcode-27`;
7. prints expected and actual `git rev-parse HEAD`;
8. fails if those SHAs differ;
9. validates the Xcode project and reference graph;
10. runs NembraCore tests;
11. runs the Xcode 27 / iPhone 12 Simulator build-test-capture script;
12. uploads Simulator screenshots/log artifacts even on a later gate failure.

A **successful Simulator job** proves only the exact software commit it exercised. A successful resolver-only/filtered workflow run proves no PR-code acceptance.

## Security boundary

The self-hosted runner must never execute arbitrary fork code or fork-controlled workflow admission logic.

The workflow therefore keeps these boundaries:

- automatic PR admission uses `pull_request_target`, so the workflow definition comes from trusted default `main`, not the PR merge commit;
- resolver executes on GitHub-hosted `ubuntu-latest` and checks out no PR code;
- workflow token permissions are explicitly read-only (`contents: read`, `pull-requests: read`);
- the live head repository must equal `jonathangana131-lab/Nembra`;
- fork heads fail closed before the Xcode job;
- automatic events additionally require live open/non-draft state plus payload-head/live-head equality;
- self-hosted checkout uses the resolver's immutable same-repository SHA, never a mutable branch name;
- trusted command filtering occurs before resolver execution;
- no secret-bearing step is added to the PR-code execution path.

Changing this workflow's trigger, same-repository guard, resolver placement, token permissions, checkout ref, or self-hosted admission `if` is security-sensitive Class-A work and requires explicit CI ownership/review.

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
