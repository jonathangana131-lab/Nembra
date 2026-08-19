# Nembra Horizon V4 — Requirements Contract, Visual Execution Rejected

Status: **functional/telemetry/state contract retained; V4 pixel-level visual execution rejected on 2026-08-19**

This handoff retains the product requirements that superseded the earlier V2/V3 concepts: speed priority, truthful propulsion, automatic recording, durable Today, unified battery interaction, Drive/Navigation/Explore transformation, motion, accessibility, and Xcode 27 performance. It no longer authorizes the V4 PNG geometry, typography, cards, map treatment, gauge placement, control layout, or material styling.

The V4 screenshots are rejected/historical simulated design evidence. Their numbers remain fixtures, not physical scooter claims. Do not faithfully reproduce or merely polish them. The next production direction must be developed through multiple internal iPhone 12 landscape composition studies grounded in this requirements contract and the selected portrait Home design language, then refined against real Xcode 27 screenshots. A first runnable composition is not acceptance.

## Historical V4 references — visually rejected

- `horizon-v4-drive.png` — rejected Drive composition; requirements/history only
- `horizon-v4-nav.png` — rejected Navigation composition; requirements/history only
- `horizon-v4-explore.png` — rejected Explore composition; requirements/history only
- `home-entry-selected-reference.png` — portrait language reference only; the separately selected portrait package remains authoritative

See `V4_COCKPIT_VISUAL_REJECTED.md` for the permanent rejection record.

## Product intent

Horizon is the primary mounted-phone experience and more than half of Nembra's purpose. It must feel like a purpose-built EV instrument cluster: Stark-level immediacy, Tesla-level hierarchy, native Apple fluidity, and an original Nembra visual language. It is not a generic dashboard, a card grid, a fake tachometer, or a prototype shell.

Nembra 1.0 is not an early-version label. This aspect is complete only when its supported states, transitions, telemetry truth, persistence, safety, accessibility, and performance are polished and stable. Do not race toward a runnable approximation.

## Non-negotiable composition

### Drive

- A large rolling speed readout is the dominant visual. The integer is primary and the decimal is subordinate but still live.
- The propulsion instrument is one perfectly symmetric white precision line. Its silhouette never changes with power.
- Gold illumination travels beneath that white line to express accepted normalized propulsion power. The gold fill must never distort the arc or make it appear crooked.
- The live marker and recent accepted peak marker remain visually distinct. The display represents propulsion power, not inferred throttle and not regenerative braking until the protocol proves those signals.
- The complete propulsion/power instrument, any tick field, glow, markers, and labels remain inside landscape safe bounds on every supported iPhone. No endpoint, tick, copy, or metric may clip. Its final geometry is chosen through the new composition studies rather than inherited from the rejected V4 arc.
- The lower durable facts occupy a spatially resolved open region and never collide with speed, propulsion, route, or controls.
- Battery is one unified tappable instrument. Its default and sole primary value is percentage (for example `73%`). One tap replaces that value inside the same instrument with accepted adaptive range (for example `8.4 mi`); another tap returns to percentage. Percentage and range are never shown simultaneously as duplicated primary readouts.
- The physical fill always represents state of charge, including while range is displayed. No detached range label or duplicate primary value may appear beside it or elsewhere.
- The value transition uses matched geometry, rolling/crossfade motion, selection haptics, a VoiceOver value that announces the current value and alternate action, and a Reduce Motion crossfade/static alternative.
- The compact landscape battery derives its engineered silhouette and material language from the selected Home battery: flatter top/bottom, controlled corners, coherent shoulder and terminal, thin cool-graphite shell, inner rim/depth, deep graphite empty region, gold charge region, SOC-clipped fine ribbing, warm internal gradient, restrained bloom, and edge light. It is not a capsule, silver fill, or detached pill terminal.
- Adaptive range remains honest: learning/unavailable/currentness states may replace the single value when required, but no numeric range is invented and no second range readout is added.
- `Today` is a calendar-day total, not the current connection session. Scooter power-off, reconnect, app relaunch, and ordinary interruption must continue the same durable day ledger.

### Navigation transformation

- Navigation emerges from and recomposes the cockpit rather than opening a square or giant floating map/card that swallows the center.
- The speed readout moves left and becomes smaller while remaining dominant enough for riding.
- The turn instruction uses one native glass control surface near the top. The route, arrival estimate, battery, connection state, and recording state remain legible.
- The map and route occupy a spatially resolved dark road world integrated with the cockpit. Flat map blocks and over-glowing route tubes are rejected. Route geometry never crosses or masquerades as the propulsion gauge.
- The propulsion instrument recomposes without changing its data meaning or chosen visual grammar.
- Starting navigation is available from the Drive screen's `Navigate` control. While navigating, that control becomes `End route`.

### Explore transformation

- Unvisited eligible roads remain graphite/grey. Confirmed ridden road segments become restrained Nembra gold. The actively discovered road gets the brightest white-gold treatment.
- A discovery event may briefly surface as one native glass notification. Do not create a permanent stack of cards over the map.
- Road geometry fades before the lower cockpit stage and cannot collide with propulsion or ride metrics.
- City coverage is durable and appears as a quiet percentage in the lower ledger. A large duplicate coverage card is not part of the selected state.
- The top action reads `Explore` while this layer is active.

### Home entry

- The selected portrait Home remains the vertical entry surface and the material/lighting language source for the new cockpit studies.
- The entire `Ready · Drive mode` row is a clear launch target for Horizon. The Mode quick control opens the mode selector and offers the same entry.
- Entering Horizon requests landscape and transitions with matched geometry from Home's battery/range language. If orientation is locked, provide one concise native instruction instead of a dead end.

## Motion contract

- Render motion at the display refresh cadence, normally 60 fps and 120 fps where ProMotion permits, without claiming that BLE telemetry itself arrives at that cadence.
- Interpolate only between accepted samples. Never invent telemetry or show false precision.
- Speed digits use a vertical odometer/rolling transition with stable baselines and no width jump. Typical change: 120–180 ms, velocity-aware, interruptible.
- Battery label toggle uses matched geometry in roughly 220–280 ms. Fill position does not jump when the label changes.
- Drive → Navigation/Explore is one coordinated transformation: existing instruments recompose intelligently, the road world emerges without a giant card, truthful values retain continuity, and the lower facts remain stable. Final geometry/timing must be measured from the new chosen composition rather than inherited blindly from the rejected V4 PNG.
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
- Keep the selected Home's white/graphite/gold palette tied to existing Nembra design tokens. Gold communicates energy, active route, and discovery—not decoration on every surface.
- Use native Liquid Glass only for functional controls/navigation chrome. The rejected giant navigation glass card, crowded bottom mega-pill, tiny segmented Drive/Nav/Explore control, and isolated top controls are not foundations for the redesign.

## Work order — complete one aspect deeply

1. Preserve and test the telemetry/persistence domain boundaries already under development.
2. Produce several internal Drive/Navigation/Explore composition studies at the real iPhone 12 landscape viewport from these requirements plus the selected Home language. Compare them together; choose and refine the strongest. Do not ask the user to accept a rough first pass.
3. Implement the chosen Drive composition using real view models plus explicit preview/UI-test fixtures.
4. Finish the one-value battery toggle, rolling speed, responsive truthful propulsion instrument, durable Today ledger, reconnect states, reduced-motion behavior, VoiceOver summaries, and all safe-area variants.
5. Profile Drive on the GitHub macOS/Xcode 27 lane; remove layout churn, dropped frames, persistent idle animation, and unnecessary invalidations before opening the next state.
6. Implement the Navigation transformation and verify road-world/gauge separation without resurrecting the rejected card composition.
7. Implement Explore road-state rendering and persistence only after Drive and Navigation meet their acceptance gates.
8. Run screenshot, unit, integration, rotation, relaunch, interruption, reconnect, accessibility, and performance checks on GitHub-hosted macOS with Xcode 27. Do not make the local Xcode 26 machine the release authority.

## Acceptance gates

- Side-by-side comparison of multiple internal studies at the real iPhone 12 landscape viewport, followed by same-state comparison of the chosen implementation against its approved production study. The rejected V4 PNGs may be used only to prove rejected traits were not revived.
- No clipping, overlap, truncated label, or unsafe interactive target.
- Speed remains readable in bright and dark conditions; contrast and Reduce Transparency are supported.
- Smooth display-cadence animation under representative live updates, with no whole-screen recomposition loop.
- One-value battery percentage/range toggle preserves SOC fill semantics, alternate-action VoiceOver, haptics, and Reduce Motion; no simultaneous/duplicate primary range appears.
- Today survives scooter off/on, app termination, reconnect, and multiple segments in the same local day.
- Navigation transformation never turns into a separate card-based dashboard.
- Explore distinguishes unvisited, visited, and newly discovered road segments and persists confirmed coverage.
- Simulation fixtures are confined to previews/tests and are visibly identified in test harnesses; release UI never implies simulated values are physical truth.
- CI evidence is produced by the GitHub Xcode 27 workflow and retained with the implementation PR.

## Explicit rejection record

- `docs/design-reference/horizon-v3/` is retained only for history and rejection evidence.
- Do not copy V3 arc geometry, clipped scooter placement, card layout, route collisions, or bottom-rail composition.
- The V4 PNG geometry, giant navigation card, flat map blocks, over-glowing route, crowded mega-pill, tiny mode control, isolated top controls, generic battery pill, and awkward spacing are also rejected. Keep the V4 PNGs only as historical evidence.
- Do not claim Horizon or Nembra 1.0 complete from screenshots alone. Completion requires the behavioral and production acceptance gates above.
