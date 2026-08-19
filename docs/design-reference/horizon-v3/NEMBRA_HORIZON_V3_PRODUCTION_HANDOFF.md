# Nembra 1.0 — Horizon Cockpit V3 Production Handoff

Status: **V3 candidate sent for user review.** The earlier V2 three-panel Option 2 board is explicitly rejected as prototype-quality. Preserve its Horizon/road-intelligence concept only; do not reproduce its geometry, thin map lines, debug labels, typography, or compressed board presentation.

## Source-of-truth visuals

- `horizon-v3-home-entry.png` — portrait Home launch module
- `horizon-v3-drive.png` — normal landscape cockpit
- `horizon-v3-nav.png` — navigation-expanded cockpit
- `horizon-v3-explore.png` — live road-discovery cockpit

The images are 2× reference renders. The landscape frames are 2580×1200 exports of a 1290×600 logical layout. Treat them as art direction and layout targets, not raster UI to ship.

## Product thesis

Horizon is an edge-to-edge road instrument, not a dashboard made from generic cards. It should feel like a premium vehicle display: smoked graphite, dimensional road and city content, precise white information, and warm gold only for live energy, route, discovery, and primary actions.

The visual hierarchy is:

1. Current speed and immediate ride context
2. Road/navigation/exploration world
3. Battery and range
4. Automatic recording and persistent daily totals
5. Secondary controls

## Home entry

Home does not contain a daily Start Ride button. When an automatic ride is active, show the compact `Open Drive Display` module. It communicates that recording is already happening, previews the landscape cockpit, and launches the dedicated landscape Dashboard scene.

If no real movement evidence exists yet, copy may read `Ready when you move`; it must not claim that a ride is active prematurely.

## Normal Drive state

- Full-canvas graphite road horizon with subtle lane depth and gold energy centerline
- Large rolling speed centered in the upper-middle; decimal is smaller but remains optically connected
- Actual scooter digital twin grounded on the road with a restrained shadow/underglow
- Acceleration presentation at leading edge and energy/range presentation at trailing edge
- Tesla/iPhone-like battery instrument at top leading edge
- Connection and ride state centered at top
- Home and Navigation controls at top trailing edge
- Persistent lower rail: automatic recording, Today, Ride Time, Odometer, City Explored, and Drive/Nav/Explore state selector

The lower rail is one grouped control/information surface. Do not convert each metric into a separate floating card.

## Battery interaction

The battery rail is tappable. It morphs between percentage-primary and estimated-range-primary states while the physical fill remains the true percentage in both states. Use one state model across Home and Dashboard so the selection is consistent. Animate the value using the same rolling-number system used throughout the app; do not crossfade the entire component.

## Navigation state

Navigation expands as the road world, not a rectangular map card. The route fills the content layer while speed compresses to the leading edge. A single glass maneuver control floats above the route; arrival information stays light and peripheral.

- Route line: warm gold edge plus bright precision core
- Current position: white center with gold halo
- Street blocks and labels: quiet graphite, sufficient contrast, no fake developer labels
- Speed always visible
- Automatic recording and daily totals never disappear
- The UI must reflow smoothly between Drive and Navigation rather than swapping unrelated screens

Use MapKit-native data/rendering where possible. Custom overlays should be vector-backed and update independently of the 60 fps speed instrument.

## Exploration state

Road exploration is a first-class mode using the same city world:

- Eligible but unvisited roads: neutral grey
- Accepted historical coverage: muted gold
- Current newly discovered road: bright gold core and restrained propagation glow
- Current position: white center with gold halo
- New road event: one transient glass control showing road name and credited distance
- City coverage: percentage plus remaining eligible miles

Coverage is calculated by eligible road length, not number of segments. Do not credit raw GPS paths until map matching and acceptance rules validate the road segment.

## Automatic ride truth

After one-time permissions and supported accessory setup:

1. Scooter powers on near the phone.
2. Bluetooth restoration/reconnection creates an automatic ride candidate.
3. Real movement evidence promotes the candidate to active recording.
4. A crash-safe journal saves samples and checkpoints continuously.
5. Scooter shutdown, temporary connection loss, backgrounding, and relaunch resume the same day without resetting Today totals.

Manual force-quit cannot be presented as fully recoverable. Auto Capture readiness must state the real limitation and tell the rider how to restore readiness.

## Motion and performance

- Speed digits use a masked vertical odometer reel at display cadence; intermediate sensor updates should be coalesced.
- Decimal, percentage, range, trip, odometer, and coverage values use the same numeric motion grammar.
- Road depth moves subtly with speed; it must not become a distracting racing-game animation.
- Navigation expansion morphs the layout: speed moves and scales, maneuver control appears, city world gains prominence.
- Discovery sends a short gold propagation along the newly accepted road, then settles into historical gold.
- Honor Reduce Motion with short crossfades and scale-free state changes.
- Keep sensor fusion, map matching, persistence, and map overlay updates off the main rendering path.
- Validate 60 fps target on supported hardware with Instruments, not only Simulator observation.

## Native Liquid Glass rules

Follow Apple’s functional-layer model:

- Use native SwiftUI Liquid Glass for interactive/navigation controls: Home, Navigation, the Drive/Nav/Explore switcher, maneuver instruction, discovery event, and Home launch action.
- Group related glass controls with `GlassEffectContainer`.
- Apply `.glassEffect(...)` after layout/appearance modifiers.
- Use `.interactive()` only for tappable/focusable elements.
- Use `glassEffectID` only for real hierarchy morphs, such as the Drive-to-Navigation control transition.
- Keep speed, road, city, scooter, telemetry, and metrics in the content layer using standard drawing/materials. Do not coat the whole screen in glass.
- Use native tab/navigation treatment on portrait screens.
- Provide accessibility-aware contrast/reduced-transparency behavior and any required availability fallback.

References:

- Apple HIG Materials: https://developer.apple.com/design/human-interface-guidelines/materials
- SwiftUI `GlassEffectContainer`: https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- SwiftUI `glassEffect`: https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)

## Accessibility and safety

- Speed, battery, range, maneuver, and readiness must remain legible in bright outdoor conditions.
- Do not make destructive/vehicle-control actions visually similar to display-mode controls.
- Keep touch targets at least 44×44 pt.
- VoiceOver must announce the battery state and toggle result, current speed without spamming every frame, navigation instruction changes, recording state, and discovery events.
- Support Dynamic Type in portrait UI. Landscape cockpit may use a constrained vehicle-display typography system but must provide accessibility labels and increased-contrast behavior.
- No interaction should require precise tapping while moving.

## Required implementation evidence

Do not call this cockpit complete from a static approximation. Completion requires:

- Xcode 27 GitHub macOS build and test evidence
- Real landscape scene/orientation behavior
- Real state integration (battery, range, connection, ride journal, metrics, navigation, exploration)
- SwiftData/persistence continuity across kill/relaunch and scooter power cycles where iOS permits
- Background/restoration readiness tests
- Map-matching and exploration acceptance tests
- Snapshot/UI coverage for Drive, Navigation, Exploration, offline/degraded, denied-permission, disconnected, and low-battery states
- Accessibility audit
- Instruments evidence for frame pacing, energy, memory, and map/sensor work

## Repository placement

Place these files under `docs/design-reference/horizon-v3/` in the Nembra repository. Keep the original 2× PNGs and this handoff. Add a short rejected marker beside the old V2 board so contributors cannot treat it as current.
