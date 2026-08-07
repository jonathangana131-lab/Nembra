# Production Dynamic Type Audit — 2026-08-06

Worker: `chat-r3x8v`  
Lane: `production-dynamic-type-audit`  
Base audited: `main@909b0c6f74af9744f33558d88185f3917e900c54`

## Purpose

Nembra's Production Visual + Performance Overhaul requires excellent accessibility and an iPhone 12 / iOS 27 acceptance loop. The merged production visual audit already identifies Dynamic Type / accessibility-size captures as missing for Home, Dashboard, Ride History, and Ride Details. This document turns that gap into a source-backed acceptance contract without taking implementation ownership from the active Home, Dashboard, shell, ride, battery, navigation, or UI-test workers.

This is a read-only QA lane plus this document. It changes no Swift source, UI tests, Xcode project, simulation scenario, battery/range model, ride evidence, Bluetooth behavior, or hardware state.

## Current Apple platform contract

Current Apple accessibility and typography guidance is clear about the target:

- support larger text and preferably Dynamic Type rather than assuming the default content size;
- use system text styles so type scales with the user's preferred size;
- make layouts adapt at all font sizes rather than merely shrinking text back down;
- keep truncation to a minimum as text grows;
- make meaningful symbols/icons remain legible at larger sizes;
- test real layouts with Larger Accessibility Text Sizes enabled;
- preserve the information hierarchy when text size changes.

Relevant Apple references:

- Human Interface Guidelines — Accessibility: https://developer.apple.com/design/human-interface-guidelines/accessibility
- Human Interface Guidelines — Typography: https://developer.apple.com/design/human-interface-guidelines/typography
- SwiftUI `DynamicTypeSize`: https://developer.apple.com/documentation/swiftui/dynamictypesize
- SwiftUI `dynamicTypeSize(_:)`: https://developer.apple.com/documentation/swiftui/view/dynamictypesize(_:)
- SwiftUI `ScaledMetric`: https://developer.apple.com/documentation/swiftui/scaledmetric
- WWDC24, Get started with Dynamic Type: https://developer.apple.com/videos/play/wwdc2024/10074/

SwiftUI exposes the standard sizes through `.xxxLarge` plus five accessibility sizes (`.accessibility1` through `.accessibility5`). Those are useful deterministic QA inputs, but an environment override is supplemental evidence: final acceptance should also exercise the actual iOS 27 Simulator preference because Nembra ships into the system environment rather than a test-only override.

Product implication: large text is a layout state, not just a bigger font. When a compact horizontal composition no longer has enough room, the production solution should recompose, wrap, or progressively disclose lower-priority content while keeping the underlying vehicle/ride truth unchanged.

## Strong foundation already present

### System/SF typography is the default

`DESIGN_SYSTEM.md` requires the system/SF family and semantic text styles in portrait wherever practical. Current Home, Ride History, Ride Details, and most Dashboard labels follow that direction with `.body`, `.headline`, `.subheadline`, `.caption`, `.title2`, and `.title3` rather than embedded custom fonts.

That gives Nembra a better starting point than a fixed-type UI. It does **not** prove the surrounding geometry can accept the enlarged results.

### Vehicle Controls is the lowest-risk current surface

`VehicleControlsView.swift` primarily composes native `Form`, `Section`, `LabeledContent`, `Button`, `Label`, and wrapping footer text. It has no app-owned fixed row height and no custom side-by-side dashboard rails.

This should still receive AX5 runtime acceptance, especially for long vehicle identity values and explanatory footers, but source-level risk is lower than Home/Dashboard/History.

### Ride Details uses native list primitives for most text

`RideHistoryDetailView` primarily uses `List`, `Section`, `LabeledContent`, `Text`, `Label`, and system navigation chrome. The 220 pt route-map height is fixed, but the surrounding textual evidence rows are not forced into app-owned fixed heights.

Large-text acceptance still needs to prove that long evidence labels/values, route error prose, and bottom content remain readable and operable. This audit does not assume native containers automatically eliminate every layout issue.

## P0 risk — Home status metrics are a fixed three-column typography trap

Current `HomeView.statusPanel` places Battery, Trip, and Mode in one `HStack`, separated by fixed 44 pt dividers.

Each `statusMetric` then uses:

- a one-line caption title;
- a one-line `.title3` value;
- `.minimumScaleFactor(0.72)` on the value;
- equal-width columns inside the same horizontal surface.

This is reasonable at default type size, but at accessibility sizes it creates the exact failure mode Apple asks teams to avoid: enlarged semantic text can be pushed back down by scaling, clipped, or forced to compete for narrow equal columns.

### Required production behavior

At large accessibility sizes, preserve all three truths without pretending the default three-column layout must survive unchanged. Acceptable production strategies include an accessibility-size-specific vertical/2-column composition, rows with label/value pairs, or another layout that keeps the battery/trip/mode values readable.

Do **not** solve this by globally capping Dynamic Type on the panel. If a local limit is ever considered for a true instrument glyph, the surrounding semantic content must still expose a fully readable large-text experience.

## P0 risk — Home controls combine fixed heights with multi-line semantic content

`HomeView.actionControl` uses a fixed `58` pt height around:

- a 36 pt circular icon;
- a title in `.subheadline`;
- a subtitle in `.caption` with `lineLimit(1)`.

At accessibility sizes, the title/subtitle stack needs more vertical room while the button height remains fixed. That is a direct clipping/compression risk and can also make status words such as `Unavailable` or `Stop to lock` harder to read.

The mode picker has a similar issue: every mode button is forced to `42` pt high inside a single horizontal row. The production visual audit already flagged the default 42 pt geometry for touch-target verification; Dynamic Type adds a second reason the segment must be revisited.

### Required production behavior

- interactive rows may grow vertically at accessibility sizes;
- critical status/subtitle text must remain available without relying on aggressive scale-down;
- mode choices must stay individually identifiable and tappable;
- if the segmented horizontal layout cannot hold the accessibility size, recompose it rather than truncating mode names;
- command confirmation semantics remain exactly the same after any layout change.

## P0 risk — Ride History row has two competing text columns

Current `RideHistoryRowView` is one horizontal row containing:

1. a fixed-width status icon;
2. date/time + continuity text;
3. a trailing stack of ODO/GPS evidence.

The merged Ride History accessibility audit already identifies this horizontal composition as an accessibility-size runtime risk. This Dynamic Type audit agrees and narrows the expected layout behavior: at larger sizes, date/continuity and evidence should not compete for a single line-width budget.

### Required production behavior

At accessibility sizes, a stacked composition is preferred if needed: identity/timeline first, evidence below. The semantic rule is unchanged — ODO and GPS evidence remain separate unless the domain can reconcile them. A larger layout must never simplify uncertainty by inventing one final distance number.

## P0 risk — automatic ride status can truncate the state the rider needs

`RideStatusStrip` uses scalable `.caption` / `.subheadline` text, but the actual `rides.statusText` is forced to `lineLimit(1)` inside a horizontal strip with a fixed 20 pt status-indicator column.

That creates a credible accessibility-size failure for strings such as restored/saving/error states. The strip is specifically where Nembra communicates automatic ride continuity, so silent truncation is more serious than cosmetic loss.

### Required production behavior

Allow the strip to grow or recompose so the meaningful ride state remains readable. If vertical space becomes expensive, reduce decorative/supporting hierarchy before truncating the authoritative ride status.

## P1 risk — Home vehicle header can become a horizontal squeeze contest

The Home header places vehicle identity/connection in a leading `VStack` and a `Locked`/`Unlocked` capsule on the trailing side of the same `HStack`.

The vehicle name is not explicitly one-line limited, which is positive, but the trailing capsule still consumes horizontal width while also scaling with Dynamic Type. Long model names or accessibility text sizes may produce awkward wrapping or compression.

Acceptance should include the real ES80 display identity and a deliberately long QA identity. At accessibility sizes, the status capsule may need to move below the identity rather than force both sides to remain horizontal.

## P1 risk — connection recovery combines prose with a trailing action

The recovery surface does one thing correctly for large text: its explanatory message uses `fixedSize(horizontal: false, vertical: true)`, so it can grow vertically.

However the message shares one horizontal row with a leading icon and a trailing progress/reconnect/settings action. AX sizes can still narrow the prose column severely.

Acceptance must cover Bluetooth off, permission denied, scooter unavailable, unsupported configuration, disconnected, connecting, and reconnecting. The action must remain discoverable and at least 44×44 pt while the full issue title/message remains readable.

## P1 risk — landscape Dashboard has fixed rails by design

Current `DashboardView` reserves fixed widths:

- left status rail: `156` pt;
- right context rail: `176` pt;
- center speed instrument receives the remaining space.

Within those rails, several user-visible values use one-line text plus `minimumScaleFactor`, including vehicle identity, mode, battery, and trip. The Dashboard's stopped mode controls also use fixed 34×34 pt label frames inside glass buttons.

This is an intentional instrument layout and cannot simply grow like a portrait `List`. But it also cannot claim Dynamic Type support merely because the labels use semantic styles.

### Dashboard-specific accessibility policy

The fixed 148 pt rolling speed numeral is a deliberate glance instrument with an authoritative VoiceOver value. It should not be treated like ordinary prose that must expand until it consumes the cockpit.

The surrounding semantic data is different: vehicle/connection, battery/range, trip/ride context, mode, and warnings must remain readable or intentionally recompose at accessibility sizes.

The production Dashboard should therefore have an explicit accessibility-size composition policy. Potential strategies include:

- changing rail widths/stacking when `dynamicTypeSize.isAccessibilitySize` is true;
- reducing nonessential labels before reducing meaningful values;
- moving secondary context into vertical groups that can wrap;
- keeping the speed instrument visually dominant while preserving semantic access to every critical state;
- ensuring stopped controls remain >=44×44 pt after any reflow.

Do not globally clamp Dynamic Type across the cockpit simply to preserve the default screenshot.

## P1 risk — speed unit/status may collide with fixed instrumentation

`DashboardSpeedInstrumentView` deliberately renders speed using `.system(size: 148, ...)` while the unit uses scalable `.title3` and the state label uses scalable `.caption2`.

At very large accessibility sizes, the unit/status can grow while the numeral retains instrument geometry. This mixed scaling policy is reasonable only if it is intentional and runtime-proven. The unit must not collide with the digits, and state text such as `LAST KNOWN` / `NO LIVE SPEED` must remain legible.

VoiceOver already announces authoritative/confirmed speed rather than transient render frames. Dynamic Type layout changes must preserve that truth boundary.

## Existing evidence gap — current Xcode gate never changes text size

`scripts/ci/xcode27_simulator_capture.sh` creates/boots the iOS 27 Simulator, runs the test bundle, installs the app, normalizes the status bar, launches simulation scenarios, and captures light/dark screenshots. It does not configure Larger Accessibility Text Sizes or another content-size category before those captures.

`NembraUITests.swift` and `RideUITests.swift` likewise launch scenarios/orientations but do not select a Dynamic Type size or assert accessibility-size layout geometry.

Therefore current green Xcode 27 runs prove only the default text-size path. Existing Home/Dashboard/Rides screenshots must not be cited as AX-size acceptance.

## Required production acceptance matrix

Use real iPhone 12 / iOS 27 Simulator evidence at coherent visual/accessibility checkpoints. Do not explode every state across every size; select sizes that expose breakpoint behavior.

Recommended minimum size sweep:

- `.large` — normal baseline;
- `.xxxLarge` — largest standard size;
- `.accessibility1` — first accessibility breakpoint;
- `.accessibility3` — strong enlargement;
- `.accessibility5` — maximum accessibility stress.

Required surfaces:

| Surface | Large | XXXL | AX1 | AX3 | AX5 | Minimum acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| connected Home | yes | spot | yes | yes | yes | no clipped metric/control text; all controls usable |
| Home recovery states | spot | no | spot | yes | yes | full issue title/message + action readable |
| active/recovered ride strip | spot | no | yes | yes | yes | authoritative ride status not truncated away |
| Vehicle Controls | spot | no | spot | yes | yes | form rows/footers readable and operable |
| Ride History | yes | spot | yes | yes | yes | date/continuity/evidence remain readable without truth collapse |
| Ride Details + route | yes | no | spot | yes | yes | labels/values/prose readable; map and bottom content reachable |
| Dashboard stopped | yes | spot | yes | yes | yes | battery/trip/mode/vehicle readable; controls >=44 pt |
| Dashboard moving | yes | no | spot | yes | yes | speed remains primary; moving/warning context remains readable |

`spot` means one representative capture/interaction is enough unless a distinct layout issue appears.

## Machine-checkable acceptance assertions

When the implementation owners have settled, prefer assertions around meaningful failure modes instead of screenshot-only approval.

Useful XCUI assertions include:

1. critical controls exist, are hittable where applicable, and retain >=44×44 pt frames;
2. key status elements have non-empty labels/values at AX sizes;
3. bottom-of-scroll content remains reachable and clear of tab chrome;
4. no critical status is replaced by an ellipsis-only/empty visual result;
5. Home metric values remain independently exposed as Battery, Scooter Trip, and Mode;
6. Ride History continues exposing separate ODO/GPS evidence semantics;
7. Dashboard speed accessibility value remains authoritative/confirmed, never a visual interpolation midpoint.

XCUI frame checks cannot prove text is visually unclipped by themselves. Pair them with exact-head screenshots and runtime inspection at the breakpoints above.

## Test architecture guidance

### Deterministic layout tests are useful

SwiftUI's `dynamicTypeSize(_:)` can force a size in previews/test hosts. Use that for fast deterministic layout development and targeted regression tests where appropriate.

Do not ship a global `.dynamicTypeSize(...)` cap just because a test override is convenient.

### Real system preference remains release evidence

Final accessibility acceptance should include at least one exact-head run where the iOS 27 Simulator itself uses Larger Accessibility Text Sizes and Nembra receives that real environment. Record how the setting was applied. If the team later automates it with Simulator tooling, prove the mechanism on the actual Xcode 27/iOS 27 runtime before treating it as evidence.

### Scaled geometry should be deliberate

When custom numeric spacing/padding truly needs to grow with text, `@ScaledMetric` is the appropriate SwiftUI primitive to consider. Do not blindly scale every constant: cockpit rails, map height, and instrument geometry need product-specific behavior rather than proportional inflation.

### Use adaptive layout instead of shrink-to-fit as the default escape hatch

`minimumScaleFactor` can be valid for bounded instrumentation, but it must not become the general answer to Dynamic Type. For normal semantic content, wrapping/recomposition should usually win over shrinking an accessibility-size selection back toward the default size.

## Active-worker integration boundaries

At this audit checkpoint, do not duplicate these owners:

- PR #70 owns `HomeView.swift` hierarchy/vehicle-status work;
- PR #57 owns Dashboard battery/readout UI, `DashboardView.swift`, `NembraUITests.swift`, and the Class-A Xcode project file;
- PR #67 owns `AppRootView.swift` / pushed-detail tab-bar shell clearance;
- PR #75 is dependent Ride History accessibility integration on the shell parent;
- PR #80 owns the separate production Reduce Motion audit;
- PR #50 owns Ride UI-test lifecycle work;
- navigation workers own the future MapKit/cockpit integration surfaces.

This document should be consumed by those owners or a later integration/accessibility lane. It does not authorize parallel edits to their paths.

## Recommended implementation order after ownership clears

1. **Home accessibility-size reflow** — status metrics, fixed-height action controls, mode picker, vehicle header, recovery row.
2. **Ride History row reflow** — stack timeline/evidence at accessibility sizes without collapsing independent distance sources.
3. **Ride status strip** — allow authoritative automatic-ride status to grow/wrap.
4. **Dashboard accessibility-size composition** — preserve fixed speed instrumentation while adapting rails/context and touch targets.
5. **Ride Details / Vehicle Controls verification** — mostly native layouts, but prove AX5 and long-content behavior.
6. **Exact-head acceptance harness** — preserve representative Large/AX screenshots and semantic/touch assertions without multiplying the suite unnecessarily.

If an incumbent implementation PR already touches one of these exact files, land the adjustment there or hand it off after merge; do not create a competing branch merely to satisfy this audit.

## Truth / hardware boundary

Dynamic Type changes presentation and layout only.

This audit does not:

- change or infer measured/estimated/display battery evidence;
- enable adaptive range or invent range;
- alter speed measurement/interpolation truth;
- change ride identity, continuity, route geometry, or distance reconciliation;
- send Bluetooth/Tuya commands or motorized-hardware writes;
- establish any physical AOVOPRO ES80 behavior;
- claim physical iPhone performance from source review;
- promote Simulator fixture values to real scooter measurements.

## Acceptance conclusion

Current main has a **good typography foundation but incomplete large-text layout proof**. Semantic system styles are common, yet the most information-dense custom surfaces still assume default-size horizontal geometry: Home's three metrics and fixed-height controls, Ride History's competing evidence columns, the one-line ride-status strip, and Dashboard's fixed rails.

Do not mark the Production Visual + Performance Overhaul accessibility-complete until those surfaces are exercised at real accessibility text sizes on the exact final iPhone 12 / iOS 27 Simulator head, with readable truth-preserving layouts and controls that remain operable.