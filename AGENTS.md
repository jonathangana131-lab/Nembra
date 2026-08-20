# Nembra autonomous development contract

This file is the execution authority for Codex and other coding agents working in this repository. It replaces the old swarm scheduler/claim/lease/mission-graph workflow as an operating model. Older `SWARM_*`, `.swarm/`, large-swarm, continuation, worker-ID, claim, lease, fencing, admission, merge-train, and capacity-mining documents are historical/reference material unless this file explicitly points to them for product or safety facts.

## Goal

Continuously move Nembra toward a finished, shippable **Nembra 1.0** with real code landing on `main`. Optimize for working product, correctness, usability, physical-truth safety, and release quality — not worker count, PR count, issue count, or coordination ceremony.

When the user says `Go`, `continue`, `keep going`, `work on Nembra`, `finish Nembra`, `finish Nembra 1.0`, or gives similarly broad authorization, begin real repository work immediately and keep working for the whole available chat turn while useful work remains. Do not answer with only a plan, status report, task list, or question about what to work on when GitHub can determine the next useful action.

A commit, PR, review, test result, merge, or one finished subsystem is a checkpoint, not a reason to stop. The loop is:

`refresh live GitHub -> finish highest-value compatible outcome -> verify/review -> integrate -> verify/fix main -> refresh -> continue`

## Source of truth

Use, in this order:

1. current `main` code and tests;
2. current open PRs, reviews, recent commits, and exact-source evidence;
3. current product/safety/release docs;
4. issues that still reproduce on current code.

Do not treat an old swarm graph, stale continuation packet, historical worker claim, old PR description, old hosted-runner gate, or old branch checklist as stronger than current GitHub reality.

## Execution independence: no environment may stall Nembra

Nembra development must not depend on one Codex quota, one chat, one Mac, one GitHub-hosted runner, or one CI provider.

- If a local/Xcode-capable environment exists, run the relevant checks directly there.
- If hosted Xcode/GitHub Actions is available, use it as supplemental execution/evidence where useful; do not make ordinary development wait merely because it is queued, unavailable, rate-limited, out of minutes, or failing before useful execution.
- If a ChatGPT/GitHub-connector session cannot execute Swift/Xcode locally, it must still inspect exact source, fix source blockers, review/repair existing PRs, integrate source-complete ordinary development work when the fast-path conditions below are satisfied, and continue with independent useful work.
- Never fake a local, Xcode, Simulator, Bluetooth, hardware, screenshot, accessibility, performance, or release PASS.
- Never add no-op churn, weaken tests, or loosen physical/release gates just to manufacture green status.

A missing execution environment is a routing constraint, not a global STOP condition.

## Development `main` versus release acceptance

`main` is the active **development integration trunk**. It is not automatic Nembra 1.0 release acceptance.

Ordinary source-complete development may merge to `main` before every final execution artifact exists when all of these are true:

- the exact diff has been reviewed;
- the change is bounded, coherent, and does not knowingly leave a fail-first/source-incomplete defect;
- current `main` and overlapping PRs were refreshed immediately before integration;
- the change does not widen physical BLE/Tuya authority, enable an unverified scooter command, fabricate telemetry semantics, expose secrets, or claim release acceptance;
- any unavailable execution is recorded honestly as `DEVELOPMENT MERGE — EXECUTION PENDING` (or equivalent), with the exact checks still required;
- later execution failures are fixed forward promptly rather than hidden or normalized.

Connector-only execution pending is **not** a PASS. It is permission for ordinary development integration to keep moving.

The fast path does **not** authorize skipping required proof for:

- Nembra 1.0 release/tag/publication;
- real-device Bluetooth/Tuya authentication or physical telemetry semantics;
- any scooter write/query/control whose safety or meaning is not already verified;
- private-key custody, signing/install provenance, credential handling, or security-sensitive release authority;
- physical iPhone/scooter evidence;
- final visual/accessibility/performance acceptance;
- any PR explicitly known to contain failing/fail-first tests or incomplete production source.

Those remain strict until the exact applicable evidence exists.

## Startup loop

At the start of a broad autonomous run:

1. Refresh `main`, open PRs, recent merges, current reviews/check results, and release-critical issues.
2. Read current `PROJECT_STATE.md` and `docs/AUTONOMY_STATUS.md` if present, but let live GitHub outrank stale prose.
3. Prefer finishing/converging a strong existing PR over creating a competing implementation.
4. If no near-merge work should be finished first, choose the highest-value current blocker to a coherent Nembra 1.0 outcome.
5. Read the affected code before changing it.
6. Implement, self-check proportionately when execution exists, review the exact diff, and integrate when current policy permits.
7. Verify/fix `main`, refresh GitHub, and continue to the next useful outcome.

Do not ask the user to choose work when this loop can decide safely.

## Coordination: GitHub, not a custom swarm database

There is **no fixed agent count** and no requirement to fill capacity. Concurrency is adaptive:

- default to one active implementation for an overlapping subsystem/root cause;
- add another writer only when the next outcome is genuinely independent in files, runtime authority, and integration path;
- reviewers/testers may work against a live candidate without spawning a competing implementation;
- when review, conflicts, execution backlog, or integration pressure grows, reduce new writing and converge existing candidates first;
- if independent work is plentiful and current candidates integrate cleanly, additional agents may work in parallel;
- optimize for merged product outcomes per unit of coordination cost, not maximum simultaneous activity.

Before creating a branch or large change, inspect current open PRs and branches for overlap. If another live PR already owns substantially the same code/problem, improve/review/fix that path when possible or choose a genuinely independent target.

Do not create successor/recovery branches merely because a task is hard, CI is pending, a chat ended, or another agent exists. One problem should converge toward one mergeable implementation.

Use ordinary short-lived Git branches and PRs as the collision and handoff mechanism. No worker IDs, mission-graph revisions, leases, heartbeats, fencing tokens, admission controller, synthetic role allocation, or stop-authority protocol is required.

## Legacy swarm and long-lived integration convergence

Historical swarm/recovery PRs are candidates, not ownership authority. Long-lived product/release branches are also candidates, not a permanent alternative trunk.

When legacy or overlapping PRs exist:

1. identify the strongest current delta against `main` by code/evidence, not by worker generation or PR age;
2. keep at most one implementation path for the same root cause;
3. transplant/rebase useful source onto current `main` when that is safer than carrying stale integration history;
4. close clearly obsolete/duplicate recovery PRs rather than stacking another recovery layer;
5. preserve useful evidence and physical-truth notes even when the old branch itself is retired;
6. prefer getting coherent source-complete slices onto development `main` instead of allowing a huge release branch to become the only place real product progress exists.

## Branch / PR / merge behavior

- Keep branches short-lived and outcome-focused.
- Do not open empty or placeholder PRs.
- Prefer a PR directly against `main` unless there is a concrete integration reason not to.
- Rebase/update/transplant stale work instead of stacking recovery PRs on recovery PRs.
- Fix review findings on the existing branch when possible.
- Close superseded/duplicate PRs rather than preserving a PR tree as process history.
- Merge source-complete ordinary development under the development-main fast path when appropriate; do not park it solely because one chat lacks Xcode or hosted execution.
- If a PR is genuinely unsafe/incomplete, record the exact blocker and move to independent work rather than weakening the gate.

## Quality gates by risk

Do not drag final-release ceremony into every small change.

For ordinary changes, run the relevant focused tests plus build/type/static checks when an execution environment is available. For user-visible iOS work, build/run the real app or Simulator and inspect the changed behavior when the environment supports it. For risky persistence, BLE, auth, concurrency, security, or architecture changes, add targeted regression coverage and validate the real boundary being changed.

Use broad release matrices, long soaks, full visual census, physical-device qualification, target iPhone evidence, accessibility/performance evidence, and whole-product acceptance at milestone/release-candidate time or when a change specifically requires them.

The exact-source Xcode 27 / iPhone 12 / iOS 27 evidence required by product policy may come from any trusted capable environment that actually ran that source (for example a Codex/local Mac, owner Mac, or GitHub-hosted macOS runner). GitHub Actions is not privileged merely because it is hosted.

Never weaken tests just to make a branch green.

## Nembra physical-truth boundary

Removing swarm bureaucracy or hosted-runner dependency does **not** weaken the scooter/physical safety boundary.

- Simulator values are not physical scooter truth.
- Do not invent BLE/Tuya protocol semantics, telemetry mappings, battery/speed/power/current/mode meanings, or command behavior.
- Historical device IDs, accounts, captures, builds, approvals, or authority do not automatically authorize a current physical run.
- Do not send scooter commands unless current product/safety docs and fresh physical evidence explicitly authorize that exact operation.
- A software/Simulator pass cannot be promoted to physical-device proof.
- Private keys, credentials, account/device identifiers, raw sensitive capture artifacts, or private signed IPAs must not be committed.
- If progress truly requires unavailable phone/scooter/account evidence, record the exact physical blocker and continue on another independent software/product task instead of manufacturing pseudo-evidence.

## Nembra Capture: when user Bluetooth input is actually required

Nembra Capture is an evidence utility supporting Nembra 1.0, not a second flagship product.

Do **not** ask the user for a fresh physical Bluetooth session merely because Capture code exists or a draft branch says “next physical rung.” The user-input milestone is reached only when current GitHub truth shows all software-side prerequisites for the intended **read-only, stationary** capture are accepted, the exact build/install path and authorization boundary are ready, physical status is no longer `NO-GO`, and the next unresolved blocker is specifically a fresh user-owned iPhone/scooter/account session.

When that happens, update `docs/AUTONOMY_STATUS.md` so `CAPTURE_USER_INPUT_READY: true`, record the exact accepted source/build and safe procedure, and state clearly what the user needs to provide/do. Until then it must remain false and agents keep developing software independently.

## Nembra 1.0 completion

Nembra 1.0 is **not done** because a unified branch exists, development `main` is busy, or a test subset passes.

`NEMBRA_1_0_RELEASED: true` may be recorded only when the bounded 1.0 product is integrated on exact release source, all applicable release blockers/acceptance gates are genuinely satisfied, physical claims remain evidence-backed, and the repository has the intended 1.0 release/tag/publication according to current release policy.

When 1.0 is actually released, update `docs/AUTONOMY_STATUS.md`, release/project state, and GitHub release notes so automated watchers and future chats can report the milestone without guessing.

Until then, broad `Go` mode continues development toward that outcome.

## Issue discipline

Fix small adjacent defects while already in the area when safe. Do not mass-mine issues to keep agents busy.

Create a new issue when a real defect cannot responsibly be fixed in the current change, requires external evidence, or deserves independent scheduling. Keep it reproducible and concise. Issue count is not progress.

## Codex behavior

Codex should treat this root `AGENTS.md` as the default repository instruction. Use repository tools, terminal commands, Xcode tooling, tests, and Git normally. If a deeper `AGENTS.md` exists, its scoped instructions may refine this file for that subtree.

For a broad prompt such as `work on Nembra until you cannot make more useful progress`, choose work from live GitHub using the loop above, make real changes, test them, commit them, integrate them, and continue rather than returning only a plan.

## Ordinary ChatGPT / GitHub-connector behavior

A ChatGPT coding session should follow the same loop with the connected GitHub repository. If it can safely edit, review, merge, or update existing work, it should do so. If its tooling cannot perform a required local/Xcode action, it must not globally stall: use GitHub-visible evidence, apply the development-main fast path where allowed, and make another useful non-conflicting contribution.

## Release behavior

The target is a coherent Nembra 1.0 release, not endless `main` churn. As release approaches, shrink the open-PR set, close obsolete branches, run the full applicable acceptance surface on the exact candidate, fix release blockers, inspect visual/accessibility/performance evidence, complete any required physical Capture rung honestly, and only then tag/publish Nembra 1.0.

The operating principle is simple:

**inspect live truth -> finish the highest-value real outcome -> verify/review -> integrate -> verify/fix main -> refresh -> continue until the bounded 1.0 release is truly complete**
