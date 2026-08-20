# PROJECT STATE

Updated: 2026-08-19

This file is a mutable snapshot. Root `AGENTS.md`, current `main`, live PRs/reviews, current code/tests, and exact evidence are authoritative. Never resume an old named branch/phase only because this file mentions it.

## Product direction

- Product: **Nembra**.
- Repository: `jonathangana131-lab/Nembra`.
- Target: a coherent, production-quality **Nembra 1.0**.
- Primary real vehicle / first hardware-validation target: **AOVOPRO ES80**.
- MAXSHOT V1S Pro remains deferred/unverified for physical validation unless newer explicit product authority changes that.
- Baseline device/runtime where applicable: **iPhone 12 / iOS 27**.
- Root `AGENTS.md` is execution authority.
- `docs/AUTONOMY_STATUS.md` contains machine-readable release/Capture user-input milestone flags.

## Current live checkpoint

At this refresh:

- development `main`: `0bc188e41c10e4deb7e8c2d214e216f6ea5b24e6`, the merged autonomous-development cutover (#3665);
- draft PR #3678: **Nembra 1.0 unified release integration**, base `main`, mergeable, current inspected head `eecadc8ea23e2156dea8f9f5bced822477da7a01`, 77 commits / 215 changed files at inspection;
- draft PR #3675: **Capture/Bluetooth checkpoint**, base `main`, mergeable, current inspected head `fb1cdc4ae82d1bcf6539790b62bb708b6984fcac`, physical/private Capture explicitly **NO-GO**;
- PR #3677: portrait Home 1.0 workstream;
- PR #3676: landscape Drive/cockpit 1.0 workstream;
- older overlapping Capture/Dashboard recovery PRs such as #3658/#3666/#3662 are candidates/history to converge, not ownership authority.

Live GitHub must be refreshed before acting because these heads can move after this snapshot.

## Development flow after Codex/swarm cutover

Nembra must not globally stall because:

- Codex quota/usage is exhausted;
- one chat has no shell or Xcode;
- one Mac/runner is unavailable;
- GitHub Actions/Xcode is queued, unavailable, rate-limited, or out of capacity;
- one PR is blocked on hardware or final evidence.

Capable agents run the relevant checks themselves. Connector-only chats continue exact-source work and may integrate bounded source-complete ordinary development under root `AGENTS.md`'s development-main fast path, recording unavailable execution honestly as pending.

This does **not** weaken physical BLE/Tuya, key/signing/custody, real-device, release, final visual/accessibility/performance, or known fail-first/source-incomplete gates.

Hosted Xcode 27 remains useful evidence when available, but it is not privileged merely because it is GitHub-hosted. Exact-source Xcode 27/iPhone 12/iOS 27 evidence may come from any trusted capable environment that actually ran the candidate.

## Current Nembra 1.0 integration truth

PR #3678 is the strongest current unified integration candidate. It already brings together substantial Capture foundations, portrait Home/Rides work, and the post-V4 Drive/cockpit foundation. It is **not** Nembra 1.0 acceptance merely because the branch exists.

The old pattern of allowing most real product development to live only on a huge release branch is not the desired steady state. Future broad `Go` work should:

1. refresh #3678/#3675/#3676/#3677 and current `main`;
2. identify coherent source-complete slices that can safely converge onto development `main` without widening unverified physical authority;
3. review/integrate those slices rather than creating more recovery ladders;
4. fix `main` forward when later execution exposes a regression;
5. keep release acceptance separate until the exact final candidate satisfies the full applicable gates.

## Capture / ES80 Bluetooth truth

Nembra Capture is the highest-value physical integration path, but it is an evidence utility, not a second flagship product.

Current Capture work contains substantial software-side foundations around typed/guided evidence, stationary authorization, provenance/custody, retained-artifact admission, and offline analysis. However current live PR descriptions still state:

- production trust/capability wiring is incomplete;
- the accepted install/app consumption path is incomplete;
- a real fresh private physical session has not been accepted;
- physical/private Capture is **NO-GO**.

Therefore `CAPTURE_USER_INPUT_READY` remains **false**.

Agents must continue software work until the exact read-only stationary carrier/procedure is genuinely ready. Only then should the status flag become true and the user be asked for the fresh iPhone/scooter/account Bluetooth evidence.

No characteristic/DP becomes Battery, Voltage, Current, Power, Speed, Throttle, Regen, ODO, Mode, Light, Brake, Range, or command semantics until repeatable physical evidence verifies source, identity, units, scale, signedness, cadence, continuity, and provenance.

Unknown BLE/Tuya writes, DP queries, unbind/reset, firmware/OTA, or guessed scooter semantics remain forbidden.

## Portrait / Home

Portrait Home is moving toward production 1.0 quality with truthful battery/range states, durable Today/ride information, narrow render invalidation, Dynamic Type/accessibility work, and selected visual direction.

Remaining acceptance is not merely source correctness. It includes exact-app runtime behavior, same-state visual critique, accessibility, performance, and a truthful production-cleared ES80 visual asset where required. Do not fabricate or AI-invent hardware details to close that gap.

## Landscape Drive / cockpit

The post-V4 Drive direction is the current cockpit foundation; old V2/V3/V4 pixels are not production authority. The target is a premium, truthful high-frequency riding surface with one-value battery semantics, rolling speed, accepted propulsion power/current-vs-peak separation, durable ride facts, stable orientation, accessibility, and bounded presentation work.

Physical speed/power/odometer/range remain unavailable until verified upstream contracts exist. Do not substitute Simulator values for physical authority.

## Persistence, rides, navigation, settings, accessibility, performance

Nembra 1.0 is broader than Capture/Home/Drive. Continue current product-quality work through:

- durable settings and recovery;
- rides/history truth and idempotent persistence;
- navigation/Explore only when their product/provider contracts are real and coherent;
- controller/keyboard/accessibility semantics where applicable;
- startup/crash/runtime failure handling;
- render performance, hitch/frame pacing, and energy efficiency;
- production visual polish and consistency across every included flow.

Anything shipped in 1.0 should be production-ready rather than a knowingly disposable prototype.

## Current milestone flags

See `docs/AUTONOMY_STATUS.md`.

At this snapshot:

```text
NEMBRA_1_0_RELEASED: false
CAPTURE_USER_INPUT_READY: false
```

`NEMBRA_1_0_RELEASED` becomes true only after exact release acceptance plus the intended 1.0 release/tag/publication. A draft PR or development-main merge is not enough.

`CAPTURE_USER_INPUT_READY` becomes true only when all software-side prerequisites for the exact read-only stationary physical rung are accepted and the next blocker is specifically fresh user-owned physical Bluetooth evidence.

## Highest-value continuation order

Recompute from live GitHub every run, but current gravity is:

1. converge the strongest source-complete parts of #3678 and its predecessor workstreams onto development `main` without carrying stale recovery topology;
2. finish the remaining software/security/install/app-consumption prerequisites for Capture while preserving physical NO-GO until they are real;
3. continue Home/Drive product closure and integrate safe coherent slices rather than parking everything behind hosted Xcode;
4. when Capture software truly reaches the user-input boundary, set `CAPTURE_USER_INPUT_READY: true`, document the exact safe procedure, and request the user's fresh physical evidence;
5. use verified physical evidence to promote only supported read-only telemetry contracts upward into the production app;
6. finish the remaining Nembra 1.0 product, persistence, navigation, accessibility, performance, visual, and release acceptance surfaces;
7. tag/publish Nembra 1.0 only after the exact candidate is genuinely accepted, then set `NEMBRA_1_0_RELEASED: true`.

## Recovery rule

A fresh chat should not trust historical Swarm Foundry rules, old worker claims, old recovery branches, old GitHub-hosted-only gate language, or this file's SHAs without refreshing GitHub.

The first meaningful action on `Go` is live repository inspection followed by real work. Keep moving while useful safe work remains in the current turn.
