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
- `docs/AUTONOMY_STATUS.md` contains machine-readable release/Capture user-input milestone flags and the current trunk-health mode.

## Current live checkpoint

At this refresh:

- development `main`: `24f5a5b310e782b65bf032de5be844542d8975d3`, with the trunk-health convergence policy merged in #3715;
- open PR count at the health snapshot: 9;
- draft PR #3675: **Capture: integrate latest fail-closed checkpoint into release candidate**, active carrier head `7a7e9461a363be91a1dfe45c98ae888eadedfeef`, 213 commits / 243 changed files at inspection, physical/private Capture explicitly **NO-GO**;
- draft PR #3678: **Nembra 1.0 unified release integration**, active head `f952ac4fe551b912fb8f121003a62b782c89db53`, 86 commits / 220 changed files at inspection, not release acceptance;
- the current root convergence policy has also been synchronized into the Capture carrier (#3716) and unified release branch (#3717), so agents operating from those branches see the same trunk-health authority as `main`.

Live GitHub must be refreshed before acting because these heads can move after this snapshot.

## Trunk health: CONVERGENCE MODE

Nembra is currently above the integration-pressure thresholds in root `AGENTS.md`. Broad `Go` work should therefore converge before spawning ordinary new work.

Current priorities while convergence mode is active:

1. shrink the open PR set by integrating, rebasing/transplanting, or closing existing work;
2. close superseded/absorbed Capture child PRs instead of preserving recovery ladders;
3. identify coherent source-complete ordinary slices on #3675/#3678 that can land safely on development `main` without widening physical authority;
4. keep only the tightly coupled trust/signing/physical-authorization chain isolated when partial integration would misrepresent authority;
5. do not create a new branch simply because a carrier moved, CI queued, or another chat ended;
6. once the queue/divergence is healthy again, update `TRUNK_HEALTH_MODE` to `normal`.

A healthy target is fewer than 5 open PRs, no unnecessary long-lived integration branch carrying ordinary finished work far ahead of `main`, and no duplicate implementation tree for the same subsystem.

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

PR #3678 remains the strongest unified integration candidate. It brings together substantial Capture foundations, portrait Home/Rides work, and the post-V4 Drive/cockpit foundation. It is **not** Nembra 1.0 acceptance merely because the branch exists.

The old pattern of allowing most real product development to live only on a huge release branch is not the desired steady state. During convergence, broad `Go` work should split/transplant coherent safe development slices toward `main`, while keeping final release acceptance separate until the exact candidate satisfies the full applicable gates.

## Capture / ES80 Bluetooth truth

Nembra Capture is the highest-value physical integration path, but it is an evidence utility, not a second flagship product.

The current Capture carrier has materially advanced software-side prerequisites, including:

- a canonical app-owned authorization session/lifecycle;
- ThisDeviceOnly replay-consumption storage;
- retained-install manifest and cross-binding contracts;
- a thin app authorization controller;
- app-container inbox/rendezvous foundations;
- signer-rendezvous contracts;
- tightened exact-head integration tests and installer chronology checks.

However current live truth still reports physical/private Capture **NO-GO**. Important remaining blockers include the independently reviewed production trust root/private-key custody, final real app lifecycle wiring, exact accepted install/container transport, exact composed execution evidence, and the later fresh physical iPhone/ES80 session.

Therefore `CAPTURE_USER_INPUT_READY` remains **false**.

Agents must continue software work until the exact read-only stationary carrier/procedure is genuinely ready. Only then should the status flag become true and the user be asked for fresh iPhone/scooter/account Bluetooth evidence.

No characteristic/DP becomes Battery, Voltage, Current, Power, Speed, Throttle, Regen, ODO, Mode, Light, Brake, Range, or command semantics until repeatable physical evidence verifies source, identity, units, scale, signedness, cadence, continuity, and provenance.

Unknown BLE/Tuya writes, DP queries, unbind/reset, firmware/OTA, or guessed scooter semantics remain forbidden.

## Portrait / Home

Portrait Home is moving toward production 1.0 quality with truthful battery/range states, durable Today/ride information, narrow render invalidation, Dynamic Type/accessibility work, and selected visual direction.

The latest unified branch includes an exact-head accessibility repair for cockpit/Home release-gate defects, but production acceptance still includes exact-app runtime behavior, same-state visual critique, accessibility, performance, and a truthful production-cleared ES80 visual asset where required. Do not fabricate or AI-invent hardware details to close that gap.

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
TRUNK_HEALTH_MODE: convergence
```

`NEMBRA_1_0_RELEASED` becomes true only after exact release acceptance plus the intended 1.0 release/tag/publication. A draft PR or development-main merge is not enough.

`CAPTURE_USER_INPUT_READY` becomes true only when all software-side prerequisites for the exact read-only stationary physical rung are accepted and the next blocker is specifically fresh user-owned physical Bluetooth evidence.

## Highest-value continuation order

Recompute from live GitHub every run, but current gravity is:

1. **converge first**: shrink the open PR set and move safe coherent source-complete slices from #3675/#3678 toward `main`;
2. finish the remaining software/security/install/app-consumption prerequisites for Capture while preserving physical NO-GO until they are real;
3. continue Home/Drive product closure without turning the unified release branch into a permanent second trunk;
4. when Capture software truly reaches the user-input boundary, set `CAPTURE_USER_INPUT_READY: true`, document the exact safe procedure, and request the user's fresh physical evidence;
5. use verified physical evidence to promote only supported read-only telemetry contracts upward into the production app;
6. finish the remaining Nembra 1.0 product, persistence, navigation, accessibility, performance, visual, and release acceptance surfaces;
7. tag/publish Nembra 1.0 only after the exact candidate is genuinely accepted, then set `NEMBRA_1_0_RELEASED: true`.

## Recovery rule

A fresh chat should not trust historical Swarm Foundry rules, old worker claims, old recovery branches, old GitHub-hosted-only gate language, or this file's SHAs without refreshing GitHub.

The first meaningful action on `Go` is live repository inspection followed by real work. If convergence mode is active, converge first. Keep moving while useful safe work remains in the current turn.