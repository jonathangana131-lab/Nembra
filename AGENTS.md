# Nembra autonomous development contract

This file is the execution authority for Codex, ordinary ChatGPT sessions using the GitHub connector, and other coding agents working in this repository. GitHub is the source of truth. Historical swarm/claim/lease/mission-graph machinery is audit/reference material only unless this file explicitly points to it for product or safety facts.

## Goal

Continuously move Nembra toward a finished, shippable **Nembra 1.0** with substantial real product outcomes reaching `main` and with Capture progressing honestly toward the smallest safe read-only physical ES80 session.

Optimize for:

- meaningful end-user/product improvement;
- source-complete subsystem closure;
- actual execution and evidence;
- healthy integration;
- physical/BLE truth and safety;
- release quality.

Do **not** optimize for PR count, branch count, worker count, test-count theater, workflow count, recovery ladders, or tiny coordination artifacts.

## Broad prompts mean FULL-BLAST execution

When the owner says `Go`, `continue`, `keep going`, `work on Nembra`, `finish Nembra`, `finish Nembra 1.0`, or equivalent, begin real repository work immediately and keep working for the whole available turn:

`refresh live GitHub -> choose/finish highest-value substantial outcome -> implement real source -> execute verification -> inspect evidence -> fix failures -> review -> merge/integrate -> verify/fix main -> refresh -> continue`

A plan, comment, test-only patch, workflow-only patch, commit, PR, review, CI run, or one merged subsystem is a checkpoint, not a reason to stop while useful work remains.

Do not ask the owner which task to choose when live GitHub can determine the next valuable non-overlapping outcome.

## FULL-BLAST OUTCOME MODE

A broad `Go` run defaults to **FULL-BLAST OUTCOME MODE**. The unit of work is a substantial coherent product outcome, not a micro-PR.

### What counts as a primary outcome

Prefer work such as:

- shipping or materially rebuilding a complete user-facing flow;
- closing a real subsystem acceptance gap across production source, tests, integration, and evidence;
- landing a major persistence/runtime/navigation/performance/accessibility improvement that changes real product quality;
- completing a meaningful Capture software rung end-to-end in the actual app while keeping physical authority fail-closed;
- integrating a coherent release-candidate slice onto `main` and fixing its integration fallout.

A primary outcome normally changes the production path plus the tests/evidence needed to trust it. There is no arbitrary line-count target, but the result should represent a meaningful acceptance or product-quality delta.

### What does NOT count as the main work of a broad Go run

Unless it is the only real blocker to a larger outcome, do not spend the turn primarily on:

- documentation-only churn;
- marker/subject files;
- test-only PRs that merely restate a known gap;
- workflow-only PRs;
- one-shot/self-mutating materializer workflows that write the real source later;
- recovery/successor branches whose only purpose is to move ancestry;
- tiny schema/alignment patches that can safely be folded into the active outcome;
- comments/status summaries.

Those may be included **inside** a substantial outcome when necessary, but they are not a substitute for implementing the product/source outcome itself.

### Direct source first

Prefer directly editing the real production source on the active outcome branch. CI/workflows should **verify** source, not act as the normal author of production source.

A temporary source-materialization workflow is acceptable only when a concrete platform/tool limitation truly requires it. It must not be treated as completion until the resulting real source exists in Git, the temporary authoring workflow is removed when appropriate, the exact resulting diff is reviewed, and required execution passes.

Do not create chains such as `test -> materializer -> recovery -> successor -> rebase-recovery` for one logical change. Keep one outcome on one branch/PR whenever practical and repair that branch in place.

### Finish the outcome, not the checkpoint

Once a worker selects an outcome, keep ownership of that outcome through as much of this lifecycle as the environment permits:

`inspect -> implement -> test/build/run -> inspect evidence -> fix -> retest -> review exact head -> integrate -> verify integration`

Do not voluntarily stop after the first test, first fix, first PR, or first green check. If the selected outcome becomes genuinely blocked, preserve the exact blocker and immediately switch to another independent substantial outcome in the same turn.

## Parallelism: spread workers across BIG independent lanes

There is no fixed worker ceiling. Parallelism is adaptive, but many agents are useful only when they are working on genuinely independent outcomes.

Default lane shape when the repository supports it:

1. **Capture authority lane — at most one active implementation writer** on the tightly coupled trust/signing/app-authorization/physical-session chain. Reviewers may inspect it concurrently, but do not spawn competing Capture implementations.
2. **Home / Rides product lane** — portrait product quality, ride history, battery/range truth presentation, interaction polish, accessibility, persistence integration.
3. **Drive / cockpit lane** — landscape riding surface, instrument behavior, orientation, render isolation, accessibility, performance, truthful unavailable states.
4. **Persistence / Settings / Navigation / runtime lane** — durable settings, recovery, idempotent storage, navigation/provider truth, startup/failure handling.
5. **Release / accessibility / performance integration lane** — exact-source acceptance, visual review, performance evidence, regression repair, integration onto `main`.

These are examples, not permanent claims. Recompute from live GitHub. If a lane already has a strong active writer, other agents must pick another independent lane or review/test the existing candidate instead of duplicating it.

**Do not let Capture monopolize every broad Go session.** Capture is a critical evidence utility, but Nembra 1.0 is the product. While one writer advances the sensitive Capture authority chain, other capable agents should advance independent Nembra 1.0 product outcomes.

## Start from live truth

Before writing:

1. Refresh `main`, this file, `PROJECT_STATE.md`, `docs/AUTONOMY_STATUS.md`, current open PRs, recent merges, checks, reviews, and the affected source/tests.
2. Inspect overlapping PRs. If a strong implementation already exists for the same root cause, finish/review/fix/verify that path rather than creating a competitor.
3. Choose the highest-value substantial outcome that is not already owned by an overlapping implementation.
4. Prefer direct-to-`main` short-lived branches for ordinary product work.
5. Use the Capture carrier or release candidate only when there is a concrete integration/authority reason.
6. Continue through implementation and verification immediately.

Chat memory and stale PR prose are context, not authority when GitHub has newer truth.

## Execution independence: no Codex quota or single machine may stall Nembra

Nembra must not depend on one Codex quota, one chat, one Mac, one GitHub-hosted runner, or one CI provider.

- If the current environment has shell/Xcode/Simulator capability, run the relevant checks directly.
- If the current interface is connector-only, actively look for a real repository runner/workflow or other available execution path that can run the exact candidate now.
- GitHub-hosted macOS/Xcode runners are valid computers when available; use them rather than waiting for an imaginary later machine.
- A runner outage/queue/checkout failure is not a global stop. Diagnose it, use another real execution path if available, or move to another substantial outcome.
- Never fake a local, Xcode, Simulator, Bluetooth, screenshot, accessibility, performance, or hardware PASS.

### No executable-behavior merge based only on `EXECUTION PENDING`

For new/modified executable product, test, tooling, or workflow behavior, source review alone is not a software PASS. Run the relevant software-verifiable checks against the exact candidate before treating it as integration-ready whenever an actual execution path exists.

If no execution path exists for that exact change, preserve the source candidate honestly as blocked from verified/integration-ready status and move to another outcome that can be completed now. Do not weaken the test or fabricate evidence.

Pure documentation/policy changes may merge after exact-diff review and consistency checks.

Physical hardware, owner measurements, private credentials, target-device facts, and genuinely human-only judgments remain external-evidence exceptions.

## `main` versus release acceptance

`main` is the active **development integration trunk**. A merge to `main` is not Nembra 1.0 release acceptance.

Ordinary product work should reach `main` continuously once it is source-complete and has the applicable software verification. Final 1.0 qualification is stricter and still requires the full applicable exact-source functional, visual, accessibility, performance, persistence, security, hardware/physical, and release evidence.

Do not make the unified release branch a permanent second development trunk.

## Trunk health without starving product development

Trunk health matters, but it must not turn every agent into a branch janitor.

Enter **hard convergence mode** when there is real collision pressure, such as:

- 8 or more open PRs **and** multiple overlapping implementations;
- 3 or more open PRs targeting the same non-`main` branch/root cause;
- duplicate/recovery/successor trees around the same implementation;
- `main` is stalled while source-complete ordinary slices are stranded off-trunk;
- merge conflicts/review backlog are actively preventing independent outcomes from integrating.

**A strict long-lived Capture carrier being many commits ahead of `main` is not, by itself, a reason to force the entire repository into convergence mode.** That condition should trigger review of what can safely leave the carrier, not freeze independent Home/Drive/persistence/product work.

While hard convergence is active:

- stop creating overlapping/recovery branches;
- close superseded attempts quickly;
- integrate/transplant safe coherent slices to `main`;
- keep the one sensitive Capture authority chain isolated when partial landing could widen or misrepresent authority;
- continue genuinely independent substantial product outcomes in parallel when they do not worsen the collision.

Exit hard convergence when the queue is small and overlap is controlled. Fewer than 5 open PRs with one implementation per root cause is generally healthy enough for full builder mode even if a strict physical-authority carrier remains long-lived.

## Branch / PR behavior

- One logical outcome should converge toward one PR.
- Keep ordinary branches short-lived and outcome-focused.
- Prefer direct-to-`main` for ordinary product work.
- Fix findings on the existing branch rather than opening a successor whenever possible.
- Fold related tests, evidence tooling, small schema repairs, and UI fixes into the primary outcome when that keeps the change coherent.
- Close superseded/absorbed PRs instead of preserving a recovery tree as process history.
- Do not open placeholder PRs.
- Do not use a workflow-only or marker-only PR as proof that a product outcome exists.

## Verification is part of implementation

The worker that changes software owns the relevant verification.

Use checks proportionate to the change, for example:

- Swift/package logic: focused `swift test` plus broader affected suites as warranted;
- app changes: exact Xcode build plus targeted unit/UI tests;
- user-visible UI: Simulator/device run and screenshot/visual inspection where the environment supports it;
- persistence: round-trip, idempotency, migration/recovery/fault cases;
- accessibility: actual accessibility audits/representative Dynamic Type and interaction paths;
- performance: actual measurement on the required environment;
- Capture security/auth: adversarial focused regression tests plus exact app integration/build evidence;
- physical BLE/ES80 claims: real supported hardware evidence only.

Fix failures instead of weakening gates. Bind evidence to the exact candidate SHA/source.

## Nembra physical-truth boundary

Full-blast development does **not** weaken physical truth.

- Simulator values are not physical scooter truth.
- Do not invent BLE/Tuya protocol semantics, telemetry mappings, battery/speed/power/current/mode meanings, or command behavior.
- Do not send unknown scooter writes/queries/controls.
- Historical device IDs, accounts, captures, builds, approvals, or authority do not automatically authorize a new physical run.
- A software/Simulator pass cannot become physical proof.
- Private keys, credentials, account/device identifiers, private signed IPAs, and sensitive raw physical evidence must not be committed.
- Missing phone/scooter/account evidence blocks only the specific physical rung; it does not block independent product development.

## Nembra Capture: user Bluetooth milestone

Nembra Capture supports Nembra 1.0; it is not a second flagship product.

Do not ask the owner for a fresh Bluetooth session merely because Capture code exists or a draft says `next physical rung`.

Set `CAPTURE_USER_INPUT_READY: true` only when current GitHub truth proves all software-side prerequisites for the exact intended **read-only stationary** attempt are accepted, the exact build/install/signing/authorization/custody path is ready, physical status is no longer `NO-GO`, and the next unresolved blocker is specifically the owner's fresh iPhone/scooter/account session.

When that happens, update `docs/AUTONOMY_STATUS.md` with the exact accepted source/build, safe procedure, what the owner must do/provide, what remains forbidden, and private-evidence handling.

Until then, keep the flag false and keep developing other software/product outcomes.

## Nembra 1.0 completion

Nembra 1.0 is not done because a branch is large, a subset of tests is green, or the UI looks good in one screenshot.

Set `NEMBRA_1_0_RELEASED: true` only when the bounded 1.0 product is integrated on exact release source, all applicable blockers/acceptance gates are genuinely satisfied, physical claims remain evidence-backed, and the intended 1.0 tag/release/publication exists.

When 1.0 actually ships, update `docs/AUTONOMY_STATUS.md`, project/release state, and GitHub release notes in the same integration window so the milestone watcher can tell the owner without guessing.

## Product priorities

Recompute from live GitHub every run, but broad autonomous work should balance the whole 1.0 product rather than funnel every worker into Capture.

High-value outcome families include:

- Capture software closure toward the safe read-only physical rung;
- portrait Home / Rides product closure;
- landscape Drive / cockpit closure;
- persistence, settings, recovery, navigation/provider truth;
- accessibility and performance;
- exact visual/product polish across included flows;
- integration of accepted large candidate work onto `main`;
- final 1.0 release qualification.

If one family has an active implementation writer, pick another independent family unless you are reviewing/testing that existing candidate.

## Stopping and handoff

There is no scheduler-owned STOP. Continue while useful independent work remains.

If tooling/runtime limits end the current turn, leave durable GitHub state with the exact branch/commit/PR, what was actually implemented and run, remaining genuine blockers, and the next concrete action. Never imply background continuation.

The operating principle is:

**refresh live truth -> select a BIG non-overlapping outcome -> implement real source -> verify it -> fix it -> integrate it -> verify main -> refresh -> keep going until Nembra 1.0 is truly released**