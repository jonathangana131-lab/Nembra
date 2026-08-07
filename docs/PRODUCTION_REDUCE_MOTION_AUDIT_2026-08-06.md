# Production Reduce Motion Audit — 2026-08-06

Worker: `chat-t5m9q`
Lane: `production-reduce-motion-audit`
Base audited: `main@045a7a7c466e049d933439f608d387658f111ebf`

## Purpose

Nembra's Production Visual + Performance Overhaul explicitly requires deliberate motion design, Reduce Motion alternatives, accessibility, and excellent iPhone 12 runtime behavior. This audit records what current source already does correctly, what remains unproven, and the acceptance contract future visual/integration owners should use without taking implementation ownership from active worker lanes.

This is a read-only QA lane plus this document. It changes no Swift source, tests, Xcode project, simulation scenario, battery/range model, ride evidence, Bluetooth behavior, or hardware state.

## Current Apple platform contract

Current Apple SwiftUI documentation exposes `EnvironmentValues.accessibilityReduceMotion` as the system preference indicating whether Reduce Motion is enabled. Apple says UI should avoid large animations when it is true, especially effects that simulate three-dimensional motion.

SwiftUI also exposes `EnvironmentValues.accessibilityPrefersCrossFadeTransitions`. Apple documents that when this is true, UI should avoid slide animations and prefer cross-fade transitions instead.

`ContentTransition` is not animation by itself: Apple's current documentation says content transitions take effect only inside transactions that apply an `Animation`. Therefore the presence of `.contentTransition(.numericText())` alone is not proof that a screen currently animates, and a future animation transaction can change that behavior.

Product implication:

- app-owned spatial/scale/rolling/camera/cockpit motion must explicitly respect system motion preferences;
- if motion is still useful under Reduce Motion, prefer a stable endpoint or an appropriate restrained cross-fade rather than merely making the same spatial animation faster;
- standard system navigation should not be replaced with custom motion solely for visual novelty;
- reduced-motion presentation must never alter telemetry truth, command confirmation, ride evidence, or persisted data.

## Source audit — current main

### Dashboard: strong existing Reduce Motion boundary

`NembraApp/Features/Dashboard/DashboardView.swift` already reads `@Environment(\.accessibilityReduceMotion)`.

Current app-owned mode/control motion is gated correctly at source level:

- the ambient gradient mode transition uses `modeAnimation`, which resolves to `nil` when Reduce Motion is enabled;
- mode scale/marker changes use the same gated animation;
- stopped-control insertion/removal uses a scale + opacity transition, but the transaction animation is disabled when Reduce Motion is enabled;
- the source preserves identical confirmed vehicle state and command semantics in both motion modes.

This is good source-level behavior, but it is not yet real Simulator acceptance evidence.

### Speed instrument: reduced-motion work is more than cosmetic

`NembraApp/Features/Dashboard/SpeedInstrumentModel.swift` has a particularly important truth/performance boundary:

- `DashboardSpeedInstrumentView` reads `accessibilityReduceMotion`;
- the 60 Hz `TimelineView(.animation(...))` is paused when Reduce Motion is enabled;
- `frame(... prefersReducedMotion: true)` snaps presentation to the latest authoritative measurement carried by the interpolator rather than rendering an invented midpoint;
- mode-related speed scale/status-opacity animations resolve to `nil` under Reduce Motion.

That is the right architectural direction: reduced motion removes unnecessary high-frequency presentation work while keeping authoritative measurement truth unchanged.

It also means final acceptance must prove both behavior and performance: turning Reduce Motion on should not leave a hidden 60 Hz redraw loop active when there is no legitimate app-owned interpolation to present.

### Rolling speed digits: explicit identity fallback

`NembraApp/Features/Dashboard/RollingSpeedValueView.swift` also reads `accessibilityReduceMotion`.

When reduced motion is enabled:

- `.numericText(value:)` becomes `.identity`;
- the brief integer-roll animation is removed;
- the displayed endpoint value remains the same presentation target.

VoiceOver is already sourced outside those transient rendered digits by the Dashboard speed instrument, so removing the roll does not require announcing presentation intermediates.

### Home: no local Reduce Motion policy yet, but current numeric transition is not automatically animated

Current `NembraApp/Features/Home/HomeView.swift` does **not** read `accessibilityReduceMotion`.

Its status metrics attach `.contentTransition(.numericText())`, but there is no local animation transaction around those values in current main. Per Apple's `ContentTransition` contract, the modifier alone does not establish active numeric animation.

Therefore the correct current conclusion is:

- there is no source proof that Home is presently performing a custom numeric roll merely because the content transition modifier exists;
- there is also no Home-owned Reduce Motion boundary ready for the future battery `% ↔ range`, integer SoC progression, or other custom motion the production overhaul requires;
- when those interactions land, their owner must gate the actual transaction/presentation planner rather than assuming the existing content-transition modifier is sufficient.

PR #70 is the incumbent `HomeView.swift` owner at this audit checkpoint. This lane must not implement a competing Home motion solution.

### Ride history / Ride Details: no custom app animation found in current root source

Current `NembraApp/App/AppRootView.swift` uses standard SwiftUI `TabView`, `NavigationStack`, `NavigationLink`, `List`, `ProgressView`, and `Map` composition. The audited current-main root source does not add an app-owned `.animation(...)` transaction around Ride History, Ride Details, or recorded-route rendering.

That is not a claim that every system transition is motionless. It means the current source does not override those major system surfaces with custom Nembra motion that requires a separate source-level Reduce Motion branch.

Future live navigation/cockpit/map-camera work will change this risk substantially and must be re-audited when it exists in the app layer.

## Primary gap — current release evidence does not prove Reduce Motion

`docs/PRODUCTION_VISUAL_CAPTURE_GAPS_2026-08-06.md` already records that the current Xcode 27 Simulator screenshot script does **not** enable Reduce Motion.

It also lists reduced-motion result states as missing for Dashboard, Home, battery/range interaction, and transition evidence.

This is the most important current gap: source contains meaningful reduced-motion behavior, but the production acceptance pipeline does not exercise it as a first-class state.

A green build with normal-motion screenshots cannot prove:

- rolling speed digits actually stop rolling;
- the Dashboard interpolation timeline is paused;
- mode/control scale transitions disappear;
- future battery integer progression snaps/reduces correctly;
- future `% ↔ range` transition is acceptable;
- future cockpit/navigation rearrangement avoids large spatial motion;
- future map-camera behavior has a reduced-motion alternative.

## Required production acceptance matrix

At a coherent integration checkpoint, run at least the following on the real iPhone 12 / iOS 27 Simulator target.

| Surface / behavior | Normal motion | Reduce Motion | Prefer Cross-Fade where relevant | Required truth check |
| --- | --- | --- | --- | --- |
| Dashboard authoritative speed update | rolling/interpolated presentation only if policy legitimately enables it | snap to authoritative endpoint; no rolling digits | n/a | same authoritative speed evidence |
| Dashboard mode change | restrained personality transition | no scale/spatial animation | optional restrained fade only when a custom transition exists | confirmed mode unchanged |
| stopped ↔ moving controls | normal insertion/removal | stable endpoint without scale motion | cross-fade may replace custom spatial transition if later designed | control availability still follows confirmed state |
| battery integer change | future bounded presentation frames only | snap or otherwise remove rolling progression | optional fade if designed | only target remains authoritative/display target; intermediates never telemetry |
| battery `% ↔ range` | deliberate interaction | stable endpoint or restrained non-spatial alternative | prefer cross-fade when appropriate | range remains estimated/unavailable truthfully |
| connection/recovery state | deliberate attention transition if later added | no large spatial movement | fade if useful | connection truth unchanged |
| ride activation/recovery | deliberate state transition if later added | no large spatial rearrangement | fade if useful | ride identity/continuity unchanged |
| navigation cockpit enter/exit | production choreography | non-spatial/reduced rearrangement | cross-fade preferred when system preference requests it | route/telemetry truth unchanged |
| map camera changes | evidence-backed camera behavior | avoid sweeping/zooming camera motion when alternative can communicate state | not a substitute for truthful map position | route geometry remains provider/recording truth |

The matrix must be expanded when new app-owned motion appears.

## How to test without creating false proof

### 1. Real system-preference acceptance

Final release evidence must include at least one run where the iOS 27 Simulator itself has Reduce Motion enabled and the app reads the real environment value. The acceptance record should explicitly state how the preference was enabled and verify the app actually observed the reduced-motion path.

Do not assume an undocumented `simctl` command changes the preference correctly. If the team later automates the setting, first prove the command/API against the targeted Xcode 27/iOS 27 runtime.

### 2. Deterministic branch tests are supplemental

A SwiftUI/test host may override an environment value to deterministically exercise reduced-motion layout/presentation logic. That is useful regression coverage, but it does not replace a real system-preference Simulator run.

For pure presentation models, deterministic unit tests should prove invariant truth such as:

- reduced-motion frame == latest authoritative target;
- no presentation intermediate is persisted as measured evidence;
- disabling visual interpolation does not change command/ride/battery domain state.

### 3. Endpoint screenshots are necessary but insufficient

Capture normal and reduced-motion endpoints, but also interact with the transition in runtime. A two-second settled screenshot cannot prove that a large scale/slide/roll occurred on the way to the same endpoint.

Use runtime observation, deterministic interaction checks, and performance evidence at coherent release checkpoints.

### 4. Performance must be inspected with motion disabled

For the Dashboard in particular, verify that reduced motion actually suppresses the high-frequency presentation path. This matters both for accessibility and iPhone 12 CPU/battery behavior.

Do not call that performance win proven from source inspection alone; inspect the real runtime when the performance lane/tooling is available.

## Cross-fade policy for future custom transitions

Nembra should not globally force opacity animations whenever Reduce Motion is enabled. Some state changes need no animation at all.

Use `accessibilityPrefersCrossFadeTransitions` only when a custom transition still benefits from temporal continuity and a cross-fade is an appropriate alternative to slide/scale/spatial movement.

A reasonable decision order for future app-owned transitions is:

1. if Reduce Motion is off, use the accepted production animation;
2. if Reduce Motion is on and motion adds no essential continuity, snap to the stable endpoint;
3. if Reduce Motion is on and a transition still benefits from continuity, use a restrained non-spatial alternative;
4. if `accessibilityPrefersCrossFadeTransitions` is true and a fade is appropriate, prefer that to slide/scale motion;
5. never animate fake telemetry or inferred physical state merely to make the transition visible.

## Active-worker integration boundaries

At this audit checkpoint, do not duplicate these owners:

- PR #70 owns current Home hierarchy and `HomeView.swift`;
- PR #57 owns Dashboard battery/readout UI, `DashboardView.swift`, `project.pbxproj`, and `NembraUITests.swift`;
- PR #33 owns Dashboard high-frequency speed-instrument performance in `SpeedInstrumentModel.swift`;
- PR #45 owns battery presentation-transition semantics in NembraCore;
- PR #67 owns pushed-detail tab-bar shell clearance;
- PR #75 is a dependent Ride History accessibility integration on the #67 parent.

This document should be consumed by those owners/integration coordinator rather than used to justify parallel edits to their files.

## Recommended next implementation ownership after dependencies settle

When the relevant owners are clear, the highest-value reduced-motion implementation/acceptance work is:

1. add an exact, reproducible iPhone 12/iOS 27 reduced-motion acceptance path to the visual/interaction gate;
2. prove the current Dashboard speed path pauses high-frequency presentation and snaps to authoritative speed;
3. add deterministic reduced-motion coverage when the `% ↔ range` and integer battery transition consumer is integrated;
4. add reduced-motion acceptance for navigation/cockpit/map-camera behavior when those app surfaces exist;
5. keep screenshots, semantic assertions, and performance evidence attached to the exact final SHA.

Do not modify active product files merely to make the test matrix easy. Acceptance must exercise the architecture that actually lands.

## Truth / hardware boundary

Reduce Motion is presentation/accessibility behavior only.

This audit does not:

- reclassify measured/estimated/display battery evidence;
- enable adaptive range;
- change speed measurement/interpolation evidence;
- alter ride lifecycle or route geometry;
- send Bluetooth/Tuya commands or writes;
- establish any physical AOVOPRO ES80 behavior;
- claim physical iPhone performance from source review.

Software/Simulator evidence must remain distinct from physical ES80 validation.

## Acceptance conclusion

Current main has a **good source-level Reduce Motion foundation in the landscape Dashboard**, including endpoint snapping and pausing the presentation timeline. The weak point is not an obvious source bug; it is that production acceptance does not yet execute reduced-motion states, and the upcoming signature battery/navigation motion has not yet been integrated.

Do not mark the final visual/performance phase complete until reduced-motion behavior is exercised on exact-head iPhone 12/iOS 27 Simulator evidence alongside normal motion and the resulting state remains truthful, usable, and performant.
