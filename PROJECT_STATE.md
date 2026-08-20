# PROJECT STATE

Updated: 2026-08-20

This file is a mutable snapshot. Root `AGENTS.md`, current `main`, live PRs/reviews, current code/tests, and exact evidence are authoritative. Never resume an old branch/phase merely because this file mentions it.

## Product direction

- Product: **Nembra**.
- Repository: `jonathangana131-lab/Nembra`.
- Target: a coherent, production-quality **Nembra 1.0**.
- Primary real vehicle / first hardware-validation target: **AOVOPRO ES80**.
- MAXSHOT V1S Pro remains deferred/unverified for current physical validation unless newer explicit product authority changes that.
- Baseline device/runtime where applicable: **iPhone 12 / iOS 27**.
- Root `AGENTS.md` is execution authority.
- `docs/AUTONOMY_STATUS.md` contains machine-readable release/Capture user-input milestones and current execution mode.

## Current live checkpoint

At this refresh:

- development `main` has moved to the full-blast outcome policy line;
- the open PR queue is small enough for builder mode rather than repo-wide convergence;
- draft PR #3675 remains the active **Capture** carrier and physical/private Capture remains **NO-GO**;
- draft PR #3678 remains the **Nembra 1.0 unified integration candidate** and is not release acceptance;
- one focused SecureLink authorization lifecycle child may own that Capture root cause; do not spawn competing implementation children.

Live GitHub must be refreshed before acting because heads and counts move quickly.

## Execution mode: FULL-BLAST OUTCOMES

Nembra is now in **builder / full-blast outcome mode**.

The previous convergence rules successfully collapsed the open queue, but they also over-focused broad Go agents on micro Capture cleanup. That is no longer the intended behavior.

A broad `Go` should now select a substantial coherent outcome and carry it through real source implementation, verification, evidence inspection, fixes, integration, and main verification. Workflow-only, marker-only, test-only, or recovery-only PRs are supporting work, not the primary outcome unless they are the only true blocker.

Direct production-source work is preferred. Do not use self-mutating/materializer workflows as the normal way to author product code. If a platform constraint truly requires one, the outcome is not complete until the actual source exists in Git, the exact diff is reviewed, the temporary authoring path is retired when appropriate, and required execution passes.

## Parallel development lanes

Many agents should spread across independent large outcomes rather than dogpile Capture.

Current lane shape:

1. **Capture authority lane** — at most one active implementation writer on the tightly coupled trust/signing/app-authorization/physical-session chain. Reviewers may inspect it concurrently.
2. **Home / Rides lane** — portrait product quality, ride history, truthful battery/range presentation, persistence integration, accessibility and polish.
3. **Drive / cockpit lane** — landscape riding surface, instruments, orientation, render isolation, accessibility, performance and truthful unavailable states.
4. **Persistence / Settings / Navigation / runtime lane** — durable settings/recovery, idempotent storage, provider truth, startup/failure handling.
5. **Release / accessibility / performance lane** — exact-source acceptance, visual review, regression repair, performance evidence, and integration of coherent accepted slices toward `main`.

These are not permanent claims; recompute from live GitHub. One implementation per overlapping root cause remains the rule.

## Trunk health

Trunk health remains important, but strict Capture branch divergence alone does not freeze the whole repository.

Hard convergence is appropriate when overlap/collision is actually high: many open overlapping PRs, several children targeting the same non-main root cause, duplicate recovery trees, stranded source-complete ordinary work, or merge/review pressure actively blocking integration.

Fewer than 5 open PRs with one implementation per root cause is normally healthy enough for builder mode even if the strict physical-authority carrier remains long-lived.

Ordinary product outcomes should prefer short-lived direct-to-`main` branches. The unified release branch must not become a permanent second development trunk.

## Development flow after Codex/swarm cutover

Nembra must not globally stall because:

- Codex usage/quota is exhausted;
- one chat has no local shell or Xcode;
- one Mac/runner is unavailable;
- one hosted workflow is queued/broken/out of capacity;
- one task is blocked on hardware or final evidence.

Agents with execution capability run relevant checks directly. Connector-only agents should actively seek a real repository runner/workflow or other available computer for exact-source software verification. GitHub-hosted macOS/Xcode runners are valid computers when available.

A runner failure is a reroute, not a global stop. Fix it, use another real execution path, or move to another substantial independent outcome.

Do not claim software PASS without execution, and do not merge new executable behavior solely as `EXECUTION PENDING`. Physical/hardware/owner-only evidence remains an honest external exception.

## Current Nembra 1.0 integration truth

PR #3678 remains the strongest broad integration candidate and contains substantial portrait Home/Rides, landscape Drive/cockpit, and Capture foundations. It is not 1.0 merely because it is large.

Use it as source/evidence to transplant or integrate coherent accepted outcomes toward `main`, not as the default home for all new feature work.

## Capture / ES80 Bluetooth truth

Capture has materially advanced software foundations around app-owned authorization sessions, replay protection, retained-install manifests, app-container inbox/rendezvous, signer contracts, capability gating, exact-artifact freeze ordering, and focused integration tests.

However physical/private Capture remains **NO-GO**. The remaining exact software/security/install/app-consumption chain must be completed and accepted before the user is asked for fresh physical Bluetooth evidence.

`CAPTURE_USER_INPUT_READY` remains **false** until the exact read-only stationary carrier/procedure is software-ready, build/install/signing/authorization/custody is accepted, physical status is no longer NO-GO, and the next blocker is specifically the user's fresh iPhone/ES80/account session.

No characteristic/DP becomes Battery, Voltage, Current, Power, Speed, Throttle, Regen, ODO, Mode, Light, Brake, Range, or command semantics until repeatable physical evidence verifies it. Unknown writes/queries/unbind/reset/OTA or guessed scooter semantics remain forbidden.

## Product quality lanes still open

### Portrait / Home / Rides

Continue production closure around truthful battery/range states, durable ride history/Today information, interaction polish, Dynamic Type/accessibility, persistence integration, visual consistency, and the truthful production-cleared ES80 asset where required.

### Landscape Drive / cockpit

Continue the post-V4 direction toward a premium truthful riding surface with one-value battery semantics, rolling speed presentation, accepted propulsion/current-vs-peak separation, durable ride facts, orientation stability, accessibility, render isolation, and performance.

### Persistence / Settings / Navigation / runtime

Continue durable settings and recovery, idempotent ride/inventory state, startup/crash/failure handling, navigation/provider truth, and product-complete included flows.

### Accessibility / performance / release

Continue exact-source accessibility, representative Dynamic Type, performance/frame pacing/energy evidence, visual review, and final release-envelope closure.

Anything shipped in 1.0 should be production-quality rather than a knowingly disposable prototype.

## Current milestone flags

```text
NEMBRA_1_0_RELEASED: false
CAPTURE_USER_INPUT_READY: false
TRUNK_HEALTH_MODE: builder
EXECUTION_MODE: full-blast-outcomes
```

`NEMBRA_1_0_RELEASED` becomes true only after exact release acceptance plus the intended 1.0 tag/release/publication.

`CAPTURE_USER_INPUT_READY` becomes true only when the next unresolved blocker is genuinely the user's fresh physical Bluetooth evidence.

## Highest-value continuation behavior

Recompute from live GitHub every run, but broad Go execution should now:

1. identify a **big non-overlapping outcome**, not a micro cleanup task;
2. keep only one implementation writer on the sensitive Capture authority chain;
3. route other agents to independent Home/Rides, Drive/cockpit, persistence/settings/navigation/runtime, accessibility/performance, and release-integration outcomes;
4. implement real source directly and fold related tests/fixes/evidence tooling into the same outcome;
5. execute relevant software verification on a real available computer;
6. review exact-head evidence and fix failures;
7. integrate coherent accepted work toward `main`;
8. refresh and immediately choose the next substantial outcome while useful work remains;
9. when Capture truly reaches the user-input boundary, set `CAPTURE_USER_INPUT_READY: true` and provide the exact safe procedure;
10. when the bounded product genuinely passes final acceptance and is tagged/published, set `NEMBRA_1_0_RELEASED: true`.

## Recovery rule

Fresh chats must not trust old swarm state, historical worker claims, stale recovery branches, old hosted-runner-only language, or this file's SHAs without refreshing GitHub.

The first meaningful action on `Go` is live repository inspection followed immediately by substantial real work.