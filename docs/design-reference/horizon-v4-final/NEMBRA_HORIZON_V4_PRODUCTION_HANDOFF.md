# Nembra Horizon V4 — Selected Production Cockpit

Status: **selected production visual target for the Dashboard/Cockpit aspect of Nembra 1.0**

This handoff supersedes every earlier cockpit mock, including all V2 and V3 Horizon images. Those earlier images are rejected references and must not be implemented, incrementally polished, or treated as layout foundations.

The V4 screenshots are simulated visual targets. Their numbers are fixtures for design verification, not claims about physical scooter telemetry. Production UI must only present accepted live or durably persisted values.

## Selected references

- `horizon-v4-drive.png` — default landscape display replacement
- `horizon-v4-nav.png` — navigation transformed into the same cockpit
- `horizon-v4-explore.png` — road exploration transformed into the same cockpit
- `home-entry-selected-reference.png` — selected vertical Home and the entry point into Drive mode

## Product intent

Horizon is the primary mounted-phone experience and more than half of Nembra's purpose. It must feel like a purpose-built EV instrument cluster: Stark-level immediacy, Tesla-level hierarchy, native Apple fluidity, and an original Nembra visual language. It is not a generic dashboard, a card grid, a fake tachometer, or a prototype shell.

Nembra 1.0 is not an early-version label. This aspect is complete only when its supported states, transitions, telemetry truth, persistence, safety, accessibility, and performance are polished and stable. Do not race toward a runnable approximation.

## Non-negotiable composition

### Drive

- A large rolling speed readout is the dominant visual. The integer is primary and the decimal is subordinate but still live.
- The propulsion instrument is one perfectly symmetric white precision line. Its silhouette never changes with power.
- Gold illumination travels beneath that white line to express accepted normalized propulsion power. The gold fill must never distort the arc or make it appear crooked.
- The live marker and recent accepted peak marker remain visually distinct. The display represents propulsion power, not inferred throttle and not regenerative braking until the protocol proves those signals.
- The complete arc, tick field, glow, markers, and labels remain inside landscape safe bounds on every supported iPhone. No endpoint, tick, copy, or metric may clip.
- The lower ride ledger occupies the open region beneath the raised arc and never collides with it.
- Battery sits at the upper left as a Tesla/iPhone-like horizontal battery instrument. Tapping toggles the center label between `73%` and `8.4 mi`; the physical fill always continues to represent state of charge.
- Adaptive range remains visible as a quiet secondary readout and clearly communicates that it is learned from this scooter.
- `Today` is a calendar-day total, not the current connection session. Scooter power-off, reconnect, app relaunch, and ordinary interruption must continue the same durable day ledger.

### Navigation transformation

- Navigation expands into the cockpit rather than opening a square map card.
- The speed readout moves left and becomes smaller while remaining dominant enough for riding.
- The turn instruction uses one native glass control surface near the top. The route, arrival estimate, battery, connection state, and recording state remain legible.
- The map and route fade into a dedicated dark lower cockpit stage. Route geometry never crosses or masquerades as the propulsion gauge.
- The propulsion gauge compresses to a smaller symmetric instrument without changing its data meaning or visual grammar.
- Starting navigation is available from the Drive screen's `Navigate` control. While navigating, that control becomes `End route`.

### Explore transformation

- Unvisited eligible roads remain graphite/grey. Confirmed ridden road segments become restrained Nembra gold. The actively discovered road gets the brightest white-gold treatment.
- A discovery event may briefly surface as one native glass notification. Do not create a permanent stack of cards over the map.
- Road geometry fades before the lower cockpit stage and cannot collide with propulsion or ride metrics.
- City coverage is durable and appears as a quiet percentage in the lower ledger. A large duplicate coverage card is not part of the selected state.
- The top action reads `Explore` while this layer is active.

### Home entry

- The selected Home remains the vertical entry surface.
- The entire `Ready · Drive mode` row is a clear launch target for Horizon. The Mode quick control opens the mode selector and offers the same entry.
- Entering Horizon requests landscape and transitions with matched geometry from Home's battery/range language. If orientation is locked, provide one concise native instruction instead of a dead end.

## Motion contract

- Render motion at the display refresh cadence, normally 60 fps and 120 fps where ProMotion permits, without claiming that BLE telemetry itself arrives at that cadence.
- Interpolate only between accepted samples. Never invent telemetry or show false precision.
- Speed digits use a vertical odometer/rolling transition with stable baselines and no width jump. Typical change: 120–180 ms, velocity-aware, interruptible.
- Battery label toggle uses matched geometry in roughly 220–280 ms. Fill position does not jump when the label changes.
- Drive → Navigation/Explore is a single 450–650 ms coordinated transformation: speed moves left, map blooms from center and fades at edges, the large propulsion arc compresses, and the lower ledger remains anchored.
- Discovery notification enters softly, remains non-blocking, and dismisses automatically. Respect Reduce Motion by replacing travel/scale with crossfades.

## Telemetry and persistence truth

- Preferred speed inputs: accepted scooter wheel speed when protocol-proven, Core Location, and Core Motion for short visual continuity. Fusion must be confidence-aware and must fall back honestly.
- The UI renderer may interpolate at display cadence; accepted telemetry and persisted facts remain the only authority.
- Propulsion presentation uses accepted watts and an observed-scale normalization policy documented in the propulsion projection/presentation contracts. Do not label the gauge `throttle`.
- Battery and range follow the battery SOC transition and adaptive range contracts already in `docs/`.
- Automatic ride capture uses Core Bluetooth restoration/background capabilities and authorized location background behavior to the extent iOS permits. It must reconnect and resume without requiring the rider to open a ride screen, while remaining truthful about OS and permission limitations.
- Daily distance and duration writes are idempotent, crash-safe, and segmented across reconnects. A scooter power cycle must not reset the day.
- Exploration operates on persisted map-matched road segments. Never mark a road covered from a visual animation alone.

## Native implementation direction

- SwiftUI is the application shell. Use a deliberately isolated high-frequency rendering surface (`Canvas`, `TimelineView`, or a measured equivalent) for speed/gauge motion so unrelated views do not invalidate at telemetry cadence.
- Use native iOS Liquid Glass for functional controls and navigation chrome on the supported SDK/runtime. Do not coat the entire cockpit in glass. Provide a visually matched fallback for older runtimes if the deployment target requires it.
- Use MapKit for navigation and exploration presentation. Keep map labels muted, route contrast high, and the lower stage dark.
- Use SF typography and real SF Symbols or the project's approved icon library. No text glyphs or improvised icons in production.
- Keep the selected white/graphite/gold palette tied to existing Nembra design tokens. Gold communicates energy, active route, and discovery—not decoration on every surface.

## Work order — complete one aspect deeply

1. Preserve and test the telemetry/persistence domain boundaries already under development.
2. Implement the Drive composition using real view models plus explicit preview/UI-test fixtures.
3. Finish the battery/range toggle, rolling numbers, full propulsion instrument, durable Today ledger, reconnect states, reduced-motion behavior, VoiceOver summaries, and all safe-area variants.
4. Profile the Drive screen on the GitHub macOS/Xcode 27 lane; remove layout churn, dropped frames, and unnecessary invalidations before opening the next state.
5. Implement the Navigation transformation and verify route/gauge separation.
6. Implement Explore road-state rendering and persistence only after Drive and Navigation meet their acceptance gates.
7. Run screenshot, unit, integration, rotation, relaunch, interruption, reconnect, accessibility, and performance checks on GitHub-hosted macOS with Xcode 27. Do not make the local Xcode 26 machine the release authority.

## Acceptance gates

- Side-by-side screenshot comparison against all three selected references at each supported landscape size.
- No clipping, overlap, truncated label, or unsafe interactive target.
- Speed remains readable in bright and dark conditions; contrast and Reduce Transparency are supported.
- Smooth display-cadence animation under representative live updates, with no whole-screen recomposition loop.
- Battery percentage/range toggle preserves SOC fill semantics.
- Today survives scooter off/on, app termination, reconnect, and multiple segments in the same local day.
- Navigation transformation never turns into a separate card-based dashboard.
- Explore distinguishes unvisited, visited, and newly discovered road segments and persists confirmed coverage.
- Simulation fixtures are confined to previews/tests and are visibly identified in test harnesses; release UI never implies simulated values are physical truth.
- CI evidence is produced by the GitHub Xcode 27 workflow and retained with the implementation PR.

## Explicit rejection record

- `docs/design-reference/horizon-v3/` is retained only for history and rejection evidence.
- Do not copy V3 arc geometry, clipped scooter placement, card layout, route collisions, or bottom-rail composition.
- Do not claim Horizon or Nembra 1.0 complete from screenshots alone. Completion requires the behavioral and production acceptance gates above.
