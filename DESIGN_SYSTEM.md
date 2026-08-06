# NEMBRA DESIGN SYSTEM — v0.3

## Personality
Quiet precision. Native iOS in portrait; instrument-grade while riding. No gamer RGB, fake carbon fiber, fake analog gauges, giant grids of glass cards, or decorative vehicle imagery that displaces useful information.

The current Home/Dashboard visuals are **functional intermediate implementations**, not the final visual target. Their existing acceptance proves current system coherence and regression safety only.

## Brand mark direction
An abstract `N` built from two route/trajectory strokes with a small forward cut. It should read as motion without looking like a racing logo.

## Typography
- System/SF family only in app UI.
- Portrait: semantic text styles wherever practical.
- Dashboard: fixed/tabular digits only where stable instrumentation requires them.
- Numeric units are subordinate and never cause width jumps.
- Final product pass must treat typography as a primary spatial/material element, not just labels placed into containers.

## Spacing
Base rhythm: 4 pt.
- micro: 4
- compact: 8
- control interior: 12
- row/group: 16
- section: 24
- major separation: 32

Use optical corrections sparingly; do not accumulate arbitrary spacing values. Final screens should minimize dead space while preserving glanceability and touch comfort.

## Radius
- compact control: 14
- regular control/surface: 20
- rare hero surface: 28
Do not stack rounded rectangles merely to manufacture “cards.”

## Materials
- Normal content: system backgrounds/secondary backgrounds and restrained depth.
- Liquid Glass: interactive chrome, floating actions, compact controls where the physical response earns it.
- Never place glass on every informational surface.
- Never stack glass panels without a hierarchy reason.
- In the final visual pass, native materials should feel integrated into the cockpit/product architecture rather than pasted on as generic cards.

## Portrait Home
1. Vehicle status and useful information outrank artwork.
2. Default hierarchy: vehicle identity + connection/lock → Battery/Trip/Mode → immediate controls → mode → vehicle details/ride context.
3. A large scooter hero is not required. Exact vehicle art is contextual and must earn its space.
4. Disconnected/reconnecting values must read as last-known, not live.
5. Safety-sensitive controls reflect obvious domain restrictions before tap, while the service remains authoritative.
6. Low battery gets semantic priority; avoid turning the entire screen into a warning theme.
7. Avoid a dashboard-card mosaic. Prefer one or two coherent grouped surfaces plus native rows.
8. Current Home is a systems-era baseline and must be substantially reevaluated during the Production Visual Overhaul once battery/ride/navigation/history data are real enough to design around.

## Color behavior
Use semantic system colors plus one restrained Nembra accent. Mode personality comes from hierarchy, motion, and subtle tint—not separate RGB themes. Red is reserved for meaningful warnings/errors, not Sport decoration.

## Motion
- Controls provide immediate pressed/haptic feedback; domain state commits only after service confirmation.
- Springs are short and interruptible.
- Reduce Motion replaces spatial transformations with fades/state changes.
- Dashboard interpolation is display-only; raw telemetry is untouched.
- Rolling digits reserve fixed geometry. Carries roll upward when value rises; borrows roll downward when it falls.
- Units/decimal precision remain stable during motion.
- Final product motion should coordinate cockpit rearrangement, navigation insertion, ride-state changes, and material transitions without creating fake telemetry or distracting from glanceability.

## Haptics
- light/selection: mode selection
- rigid/medium: confirmed lock action where appropriate
- success: important command confirmation sparingly
- error: failed command/invalid performance test
- never haptic-spam continuously changing telemetry
- final product pass must audit haptics screen-by-screen rather than adding them as decorative feedback.

## Landscape Dashboard principles
1. Dashboard is a dedicated cockpit, not portrait Home rotated.
2. Speed is dominant and glance time minimal.
3. Battery/mode/connection/ride distance remain visible without competing with speed.
4. Stopped controls disappear or reduce while moving.
5. Navigation transforms the same composition rather than opening a separate-looking page.
6. Mode personality is subtle and must not hurt readability.
7. Battery/connection warnings outrank decorative telemetry.
8. Render rate may exceed sensor rate, but visual frames are never stored as measured telemetry.
9. The final cockpit must avoid developer-dashboard rails, giant unused black regions, generic cards, and prototype-looking strips.
10. Navigation, live ride state, battery/range, trip, and duration should participate in one adaptive composition rather than feeling like independently stacked widgets.

## Landscape speed instrument — Phase 10 accepted rules
- The speed instrument is a dedicated center subtree; high-frequency visual refresh must not invalidate the whole Dashboard.
- Its SwiftUI animation timeline may run at up to 60 Hz only while a real render-only interpolation window is active and pauses when the transition is complete.
- Ordinary production launch does not animate between uncalibrated samples. It snaps to authoritative measurements until real MAXSHOT cadence/latency/resolution is measured and a hardware policy is explicitly selected.
- Explicit Simulator QA may inject a bounded presentation policy to exercise transitions. Those values are never presented as MAXSHOT behavior.
- Fixed digit slots preserve center geometry through transitions such as 9↔10; the current MAXSHOT display reserves two integer slots because its verified supported speed range fits them. Future vehicle capability changes must revisit geometry rather than silently clip.
- Integer rolling is subordinate to measured-sample interpolation, not a second smoothing or prediction layer.
- MPH stays visually subordinate to the numeral while maintaining a stable baseline and enough separation to avoid looking attached to one digit.
- VoiceOver announces the latest authoritative/confirmed speed, never an unmeasured interpolated midpoint.
- Real iPhone 12/iOS 27 Simulator screenshot acceptance checks center dominance, digit width, unit alignment, clipping, side-rail stability, safe areas, and moving/stopped-control behavior. Still screenshots prove composition only; temporal smoothness requires runtime tests/profiling.

## Landscape confirmed-mode personality — Phase 11 accepted rules
- Mode personality is a **presentation system**, not a vehicle-performance model.
- Its input is only the scooter-confirmed `RideMode?`; tapping a mode control does not authorize visual state by itself.
- Unknown mode remains visually neutral/quiet rather than defaulting to Sport or another invented state.
- Walk → Eco → Drive → Sport may increase visual energy gradually, but the progression must remain restrained enough that speed, battery, connection, and safety warnings keep their established hierarchy.
- Accepted personality levers are limited to subtle center ambient intensity, speed-instrument scale, mode-readout scale/marker, and secondary status emphasis.
- Do not introduce per-mode RGB themes, neon glows, fake carbon, warning red for Sport, fake tachometers, fake throttle/power meters, or invented range/efficiency implications.
- The side rails and center digit geometry remain fixed. Mode changes must not cause cockpit reflow or make one mode occupy materially different layout space.
- Sport may feel more energetic but must not look dangerous, alarmed, or game-like.
- Walk may feel calmer but must not look disabled or low-contrast.
- Drive is the visual baseline; Eco is a restrained intermediate state.
- Reduce Motion removes the snappy/spatial personality transition while preserving the confirmed state change and final visual hierarchy.
- Mode personality never changes telemetry, speed-limit semantics, ride evidence, command confirmation, history, distance, or persistence.
- It never implies a MAXSHOT mapping from Walk/Eco/Drive/Sport to DP101/DP102/DP103 until real hardware evidence proves that relationship.
- Acceptance requires real iPhone 12/iOS 27 captures for the personality extremes and intermediate states plus a moving-state capture. Source inspection or static mockups alone are insufficient.

### Phase 11 visual baseline accepted 2026-08-06
Real XCTest attachments from Xcode 27 run `31063560164` were reviewed for Walk, Eco, Drive, Sport, confirmed Sport, and moving Drive.

Accepted observations:
- Walk is calmer without looking unavailable.
- Eco increases emphasis slightly without becoming a theme change.
- Drive remains the balanced baseline.
- Sport is noticeably stronger but still monochrome, instrument-grade, and subordinate to actual safety/status information.
- center speed remains dominant and unclipped.
- mode transitions do not disturb side-rail placement or stopped-control geometry.
- moving state keeps state-changing controls unavailable and preserves the accepted safety hierarchy.
- no excessive glow, safe-area clipping, or landscape crowding was observed.

These captures are the accepted **intermediate baseline**, not final visual/product acceptance.

## Production Visual Overhaul / Final Product Design Pass — mandatory future milestone
This is a release-quality gate, not optional polish.

### Product quality target
The final visual system should feel like a world-class native iOS 27 mobility product with premium modern EV instrumentation. Stark and Tesla may be used as a quality reference for refinement and cockpit confidence, but Nembra must remain original and scooter-aware rather than copying either.

Required qualities:
- huge beautiful rolling MPH as the primary glance target.
- truthful battery presentation with high-resolution percentage behavior only where telemetry supports it.
- elegant range/trip/duration hierarchy driven by real data.
- navigation deeply integrated into the cockpit and able to dynamically rearrange the composition.
- polished live ride information.
- restrained meaningful Eco/Drive/Sport personalities.
- original premium scooter-aware graphics where they improve comprehension.
- native materials/Liquid Glass with depth and restraint.
- excellent typography, spacing, animation, accessibility, and haptics.
- minimal wasted space.
- no giant empty black regions, developer-dashboard rails, generic card mosaics, placeholder surfaces, or obviously prototype-looking layout decisions.

### Required design loop
For every major screen before final visual acceptance:
1. capture the current real Simulator screenshot.
2. critique it against the master vision and truthful available product data.
3. redesign substantially where needed.
4. implement production SwiftUI/domain state.
5. build/run/interact on iPhone 12/iOS 27.
6. capture real screenshots.
7. critique again.
8. repeat until product-level quality is achieved.

Required coverage:
- portrait Home.
- landscape Dashboard without navigation.
- landscape Dashboard with navigation and dynamic rearrangement.
- live ride states.
- battery, charging, and low-battery states where supported.
- completed rides/maps.
- history/stats.
- leaderboard when implemented.
- controls/settings.
- major connection, permission, unsupported-hardware, persistence, and recovery error states.

A technically correct screen that looks mediocre is **not accepted as final**. Functional Simulator screenshots and clean layouts are necessary gates but never sufficient to declare Nembra visually complete.
