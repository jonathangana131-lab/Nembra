# PROJECT STATE

Updated: 2026-08-07

This file is a **mutable coordination snapshot**, not a higher authority than GitHub. Before acting, inspect live `main`, open PRs, active branches, recent commits, and current Actions/Xcode runs. If this file disagrees with live GitHub, **GitHub wins**.

## Product direction
- Product: **Nembra**.
- Repository: `jonathangana131-lab/Nembra`.
- Primary real vehicle / first hardware-validation target: **AOVOPRO ES80**.
- Deferred/unverified profile candidate: **MAXSHOT V1S Pro**. Preserve accepted abstractions, tests, simulation work, and generic vehicle architecture; do not prioritize MAXSHOT-specific physical validation.
- Baseline device/runtime target: **iPhone 12 / iOS 27**.
- Permanent engineering/product charter: `MASTER_CONTINUATION_DIRECTIVE.md`.
- Nembra must feel like premium native vehicle software while preserving strict separation between measured, estimated, retained, interpolated, derived, Simulator, public-research, and physically verified evidence.

## Live checkpoint
Checkpoint captured from GitHub on 2026-08-07:
- `main`: `58ba1958a78f3410fc53e549e04398e43204fe25`.
- That head merged PR #299, **accepted-power propulsion-gauge accessibility**.
- This SHA is a checkpoint only. Resolve the current head again before any write, gate, merge, or recovery decision.

Recent accepted `main` work materially newer than the previous project-memory snapshot includes:
- #272 — transcript-wide Tuya candidate receipt chronology.
- #287 — telemetry benchmark rejected-sample chronology / continuity hardening.
- #285 — field-specific live speed currentness domain.
- #290 — lifecycle-owned ride-duration observation segments.
- #281 — ride-distance rejected-sample chronology.
- #294 — Liquid Glass interactivity follows actual control availability.
- #296 — highest accepted propulsion-power measurement evidence.
- #299 — propulsion-gauge accessibility remains pinned to accepted power, not interpolated display frames.

The old `feature/ride-location-capture` / PR #8 handoff is historical and must **not** be resumed merely because older prose names it.

## Current maturity by product area

### ES80 passive capture / Tuya research
This remains the highest-value physical-integration path.

`main` already contains bounded public-family Tuya offline-analysis foundations, including transcript chronology. The complete passive CoreBluetooth capture runtime/product shell is still moving through active recovery/dependency branches rather than being a finished production read-only ES80 service on `main`.

Important active coordination snapshot:
- #297 — final passive-capture runtime recovery/hardening.
- #307 — repeated stock-app marker correlation recovery on the hardened capture runtime.
- #305 — passive-capture → Tuya candidate bridge recovery, dependency-bound to the accepted passive runtime and final analyzer chronology.
- #301 — exported capture artifact → deterministic offline framing report, downstream of the bridge.
- #303 — product-facing Nembra Capture app recovery, still dependency-sensitive to passive runtime movement.
- #295 and its dependent DP-analysis chain — generic structural DP research on current-main ancestry.

These are **software research tools**, not physical ES80 protocol verification. No characteristic/DP becomes Battery, Voltage, Current, Power, Speed, Throttle, Regen, or a command until repeatable physical evidence verifies source, identity, units, scale, signedness, cadence, continuity, and provenance.

The next real hardware milestone is not more speculative decoding. It is a short, safe, passive physical capture produced by accepted Nembra tooling and analyzed offline without random Bluetooth writes.

### Propulsion / power
`main` now has a substantially stronger truth-preserving domain stack:
- accepted propulsion-power presentation chronology;
- render-only smoothing separated from measurement evidence;
- accepted-power accessibility projection;
- accepted observed peak-power evidence;
- learned observed-power-envelope foundations.

Active #302 is recovering/durably persisting learned observed envelope calibration and bridging retained calibration back into presentation scale.

This stack is **not yet proof of a physical ES80 power/current source** and is not a rated motor/controller maximum, throttle-position signal, or regen proof. Production ES80 power integration remains gated on physical field verification.

### Speed / cockpit currentness
`main` contains field-specific speed currentness (#285), but application/provider and cockpit control-policy integration is still being reconciled in active lanes.

Relevant active work includes #293 and dependent/interim Dashboard work such as #282, plus the dedicated Dashboard performance lane #255 and related formatting work. `DashboardView.swift`, speed-model tests, and several app/UI-test surfaces are therefore high-contention. Do not create a competing Dashboard implementation.

### Battery / adaptive range
The permanent direction remains unchanged:
- one authoritative battery evidence/currentness domain;
- `% ↔ estimated remaining range` as a direct primary interaction;
- range learned from this specific ES80's legitimate battery consumption vs real ride distance;
- no advertised-range × SoC final formula;
- no invented current, watts, Wh/mi, voltage, charging state, or 1% raw resolution.

There are multiple active/recovery dependency lanes for battery receipt identity, range authority, learning-window assembly, persistence, and presentation. Treat them as dependency work to reconcile, not invitations to build duplicate models.

Stock Tuya Battery / Voltage / Current / Power values remain **correlation anchors** until their underlying physical transport/DP semantics are verified.

### Rides / history
Accepted ride evidence continues moving upward:
- lifecycle duration evidence is on `main`;
- ride-distance chronology is hardened on `main`;
- active #300 joins monotonic duration into durable completed-history truth;
- active #306 binds accepted peak-power evidence to ride truth;
- ride-detail/logbook and recent-ride Home presentation have separate active owners.

Keep ODO, GPS distance, integrated speed distance, route geometry, duration coverage, peak evidence, and unavailable/partial states distinct. Do not derive missing duration from wall-clock subtraction or invent a single reconciled distance where the durable schema does not support one.

### Navigation
Navigation foundations remain active. #309 is the current recovery for collision-resistant route-request identity. Other navigation evidence lanes may be dependency-bound or stale; inspect live ownership before touching planning, guidance, reroute, arrival, or MapKit adapter files.

### Product visual closure
Production UI is not considered finished merely because systems build and tests pass. Home, Dashboard, Vehicle Controls, Ride Details, app icon/system surfaces, Dynamic Type, accessibility, and performance each have active or recently active owners.

Before taking app-visible work, inspect current PR path overlap. For visual changes, acceptance remains: real iPhone 12 / iOS 27 Simulator interaction + screenshots + critique + accessibility/performance review where relevant.

## Active-worker rules
- One chat owns one isolated branch/lane.
- Existing changing branches/PRs are presumed owned.
- Do not push to another worker's branch.
- Recover abandoned work on a **new** recovery branch from its exact durable head.
- Avoid high-contention integration surfaces (`project.pbxproj`, root/bootstrap/persistence wiring, global project-memory files, Dashboard/Home files) unless the lane is clearly unowned and the change is necessary.
- Before deep work and before merge, refresh live PR/file overlap.
- Queued, skipped, cancelled, stale-SHA, resolver-only, or ancestor CI is not exact-head acceptance.

## Highest-value continuation order
Use live GitHub to choose the highest-value **safe, non-conflicting** slice. At this checkpoint the strongest product gravity is:

1. Finish the hardened passive ES80 capture runtime lineage and re-anchor accepted passive capture onto current `main` without flattening provenance/continuity guarantees.
2. Reconcile downstream marker correlation, capture→Tuya bridge, offline report, and product-facing Nembra Capture shell onto that accepted lineage.
3. Perform one minimal, safe, passive stationary physical ES80 capture with the accepted research build; preserve the artifact unchanged and analyze it offline.
4. Use repeated physical stock-app correlation to verify read-only field candidates. Only after raw source/scaling/signedness/cadence/provenance are repeatable may Battery / Voltage / Current / Power move toward production telemetry authority.
5. When a verified production signal exists, move upward quickly into read-only vehicle-service integration, battery/range or propulsion presentation, runtime QA, accessibility, performance, and final visual polish rather than endlessly expanding research primitives.
6. In parallel, continue already-owned ride/history/navigation/battery/product-UI lanes through their dependency and exact-head acceptance gates without duplicating them.

If the active dependency graph has materially changed, recompute this order rather than following the numbered list mechanically.

## Physical truth still unresolved
Do not claim these as verified until real ES80 evidence proves them:
- stable physical advertisement/peripheral identity suitable for production/persistence;
- authoritative GATT service/characteristic/notification identity;
- Tuya family/framing compatibility on the physical target;
- DP IDs/types/scales/signedness/units/cadence for Battery, Voltage, Current, Power, Speed, ODO/trip/mode/control fields;
- throttle position or regen semantics;
- command authorization/acknowledgement/state confirmation;
- physical speed cadence/quality policy;
- stable battery 1% resolution, voltage behavior, charging semantics, or energy telemetry;
- physical iPhone 12 runtime/performance and outdoor ride/location behavior.

## Recovery rule for future chats
Do **not** trust an old named phase, PR, branch, or SHA from this file without checking GitHub first. The first meaningful action in a fresh chat should be live repository inspection. Resume the newest safe unfinished action from live state; never regress to the obsolete PR #8 handoff.