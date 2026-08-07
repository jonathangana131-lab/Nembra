# Exact-head Xcode 27 PR gate

Updated: 2026-08-06

## Purpose

Nembra needs Xcode 27 / iPhone 12 Simulator acceptance tied to an immutable pull-request head, without allowing fork-controlled workflow code or fork PR code onto the self-hosted `xcode-27` runner and without silently treating stale CI as proof for a newer commit.

`.github/workflows/xcode27-pr-command.yml` supports two request families:

- automatic acceptance requests from same-repository non-draft PR lifecycle events, admitted by a **trusted default-branch workflow**;
- an explicit trusted `/xcode27` PR conversation command.

The workflow resolves the current PR on a GitHub-hosted runner before any PR code can reach `xcode-27`, then revalidates the frozen candidate again on the self-hosted runner **before checkout**.

## Why automatic admission uses `pull_request_target`

This repository is public and the acceptance job uses a self-hosted runner.

GitHub documents an important trust difference:

- `pull_request` runs workflow bytes from the PR merge commit, so a fork controls the workflow definition that GitHub is evaluating;
- `pull_request_target` runs workflow bytes from the base repository's default branch.

A same-repository check written **inside a fork-controlled `pull_request` workflow is not a sufficient self-hosted admission boundary**, because a malicious fork can propose changing or deleting that check before the job is admitted.

Nembra therefore uses `pull_request_target` for automatic PR admission so the resolver and `runs-on: xcode-27` decision originate from trusted default-branch workflow bytes.

`pull_request_target` is a privileged event and must be treated accordingly. This workflow keeps explicit read-only token permissions and executes no PR code on the hosted resolver. It does **not** check out a fork head. The self-hosted job is reachable only after the trusted resolver verifies the live head repository is exactly `jonathangana131-lab/Nembra`, and its first step revalidates the live candidate before any PR checkout.

GitHub also warns generally against exposing self-hosted runners to public-repository fork code. Runner-group workflow restrictions/ephemeral isolation remain valuable defense in depth, but the repository workflow must fail closed even when those external settings are unknown.

Reference guidance:

- GitHub Docs: `Securely using pull_request_target`;
- GitHub Docs: `Secure use reference`;
- GitHub Docs: `Managing access to self-hosted runners using groups`;
- GitHub Docs: `Control the concurrency of workflows and jobs`.

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
6. if the PR changes while it remains ready, the new SHA receives a distinct candidate gate rather than relying on ordering between old/new jobs;
7. merge only when the required successful checkout/QA steps correspond to the final unchanged acceptance head.

Draft PR checkpoint churn does not intentionally consume the self-hosted acceptance gate.

## Delayed PR-event freshness guard

A `pull_request_target` webhook payload is evidence about the event GitHub emitted. It is **not** automatically current PR truth when delivery is delayed or processed out of order.

This mattered during the 2026-08-06 GitHub Actions incident. PR #50 provided a concrete pre-fix sequence under the older `pull_request` trigger:

- run `31129569763` resolved delayed event head `bfabe8e7...` after the live PR had already advanced; its Xcode job was later cancelled;
- run `31130118936` resolved later-but-still-stale event head `a9db1a09...` after another PR advance and also ended cancelled;
- a later run finally targeted the then-current `3cb6e7ad...` head.

Decoded resolver logs from run `31129569763` show the pre-fix automatic path directly assigned `context.payload.pull_request` and output its head SHA without live-fetching the PR.

The gate now has **two** freshness boundaries.

### 1. Hosted resolver freshness

The GitHub-hosted resolver live-fetches the PR for every accepted trigger.

For an automatic `pull_request_target` event, the candidate is admitted only when all of these remain true at resolver time:

- the live PR is open;
- the live PR is not draft;
- the live head repository is Nembra itself;
- the event payload `head.sha` exactly equals the live PR's current `head.sha`.

If the payload head is already stale, the resolver records a notice and returns `should_run=false`; no self-hosted job is created for that event.

### 2. Self-hosted pre-checkout freshness

Resolver output is still only a point-in-time snapshot. A PR can advance **after** a once-valid resolver finishes but **before** its dependent self-hosted job begins.

The first step on `xcode-27` therefore live-fetches the PR again using trusted workflow code before checkout. It requires:

- the live head repository is still Nembra;
- the live `head.sha` still equals the frozen candidate SHA;
- for automatic gates, the live PR is still open and non-draft.

If that second check fails, every checkout/build/test/capture step is skipped. No PR code is checked out or executed by that stale job.

This second boundary is required because GitHub concurrency ordering is not guaranteed by workflow dispatch order. A once-valid old resolver cannot be assumed to reach concurrency before a newer head.

The guard still does **not** claim a PR can never change after the self-hosted preflight. The candidate remains an immutable SHA and final acceptance always compares the completed evidence with the final unchanged PR head. If the live PR advances after preflight, the old job cannot cancel the new head because concurrency is SHA-scoped, and its eventual result is stale/non-acceptance evidence.

## Filtered workflow/job success is not acceptance

GitHub can report skipped conditional steps/jobs as successful/skipped rather than failing required checks. With the second freshness boundary, a stale candidate may also start `simulator-qa`, complete only its trusted preflight, skip checkout/QA, and leave that job green.

**Neither top-level workflow success nor `simulator-qa: success` by itself is the acceptance signal.**

Exact-head acceptance requires all of the following:

- the self-hosted live revalidation allowed the candidate to proceed;
- `Checkout immutable PR head` actually ran and succeeded;
- `Verify immutable PR head` actually ran and proved expected SHA == actual checkout SHA;
- required project/package/Simulator QA steps actually ran and succeeded;
- the candidate SHA is still the unchanged final PR head at acceptance time;
- required logs/artifacts were produced and inspected according to the lane's acceptance needs.

A resolver-only success, a hosted-filtered workflow, or a self-hosted preflight-only success is **diagnostic/non-acceptance evidence**, even if GitHub renders the workflow/job green.

Automation that gates merges must inspect the exact checkout/QA step evidence, not only workflow/job conclusion.

## Bootstrap/backlog caveat

Workflow changes do not retroactively rewrite already-created workflow runs. A delayed event associated with a pre-fix workflow version can still execute that older resolver after this change reaches `main`.

During rollout, old backlog events must therefore be classified by their actual resolver workflow bytes/logs or equivalent run/ref evidence. A pre-fix delayed event that still trusts `context.payload.pull_request` is historical backlog, not evidence that the new default-branch guard regressed.

Post-bootstrap stale-event proof must show the trusted default-branch resolver/preflight version containing both live freshness checks before drawing conclusions about the new guard.

## Optional trusted `/xcode27` command

On a Nembra pull request, an owner/member/collaborator may add this exact PR conversation comment:

```text
/xcode27
```

The workflow-level filter requires the exact body and trusted GitHub author association. `issue_comment` evaluates the workflow definition from the default branch, so this admission path does not trust PR-proposed workflow bytes.

The resolver live-fetches the PR and freezes its **current** head. This manual path deliberately remains distinct from automatic ready-PR gating: it does not inherit the automatic event's non-draft requirement.

The same-repository check still applies before self-hosted execution. The self-hosted pre-checkout freshness step also requires the frozen SHA to remain the current same-repository head; for manual gates it does not require the PR to remain non-draft/open.

Historical note: early during the 2026-08-06 Actions incident, connector-created comments appeared to produce no run at the immediate observation point. Later backlog recovery showed delayed `issue_comment` workflow delivery. That incident evidence should not be generalized into a permanent claim that connector-created comments never trigger Actions.

## Exact-head behavior

For a valid request the trusted workflow:

1. live-fetches the PR on GitHub-hosted `ubuntu-latest`;
2. verifies the current head repository equals Nembra;
3. for automatic PR events, rejects stale payload heads or a live draft/closed PR;
4. freezes the live current `head.sha` and trigger class;
5. creates a self-hosted candidate job only when hosted admission passed;
6. scopes concurrency to PR number **and frozen SHA**;
7. live-fetches/revalidates the PR again on `xcode-27` before checkout;
8. if stale at that point, skips all PR checkout/QA work;
9. otherwise checks out the immutable same-repository SHA;
10. prints expected and actual `git rev-parse HEAD` and fails if they differ;
11. validates the Xcode project and reference graph;
12. runs NembraCore tests;
13. runs the Xcode 27 / iPhone 12 Simulator build-test-capture script;
14. uploads Simulator screenshots/log artifacts for candidates that actually proceeded through QA.

Only a candidate whose live preflight, immutable checkout/verification, and required QA steps actually succeeded can become acceptance evidence.

## Security boundary

The self-hosted runner must never execute arbitrary fork code or fork-controlled workflow admission logic.

The workflow therefore keeps these boundaries:

- automatic PR admission uses `pull_request_target`, so the workflow definition comes from trusted default `main`, not the PR merge commit;
- the first resolver executes on GitHub-hosted `ubuntu-latest` and checks out no PR code;
- workflow token permissions are explicitly read-only (`contents: read`, `pull-requests: read`);
- the live head repository must equal `jonathangana131-lab/Nembra` before the self-hosted job can be admitted;
- fork heads fail closed before the Xcode job;
- automatic events additionally require live open/non-draft state plus payload-head/live-head equality;
- the first self-hosted step is trusted live metadata revalidation and runs before PR checkout;
- self-hosted checkout uses the frozen immutable same-repository SHA, never a mutable branch name;
- all PR-code execution steps are conditional on the second live freshness result;
- trusted command filtering occurs before resolver execution;
- no secret-bearing step is added to the PR-code execution path.

Changing this workflow's trigger, same-repository guard, resolver placement, token permissions, concurrency key, pre-checkout revalidation, checkout ref, or self-hosted admission conditions is security-sensitive Class-A work and requires explicit CI ownership/review.

## Concurrency

Simulator concurrency is scoped by **resolved PR number plus frozen candidate SHA**:

`nembra-xcode27-pr-command-<PR_NUMBER>-<HEAD_SHA>`

with `cancel-in-progress: true`.

This deliberately changes the old PR-only cancellation model.

- duplicate gates for the **same exact SHA** may supersede one another;
- different SHAs for the same PR cannot cancel each other, so a late old job cannot cancel a newer head merely because it reached concurrency later;
- if an old once-valid head reaches a runner after the PR advanced, the self-hosted pre-checkout revalidation filters it without checking out PR code;
- if a head becomes stale after preflight, it may finish as stale diagnostic work, but it cannot cancel a different newer SHA and cannot become final acceptance because the final PR SHA comparison fails;
- unrelated PRs remain isolated as before.

GitHub does not guarantee concurrency ordering by workflow dispatch time, so correctness must not depend on "newer event arrives last" assumptions.

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
