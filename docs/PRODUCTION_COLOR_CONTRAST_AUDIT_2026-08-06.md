# Production Color + Contrast Audit — 2026-08-06

Worker: `chat-n4c7p`  
Lane: `production-color-contrast-audit`  
Protocol: Nembra Swarm OS v7

## Purpose

Define a source-backed accessibility acceptance contract for Nembra's current color, contrast, transparency, and non-color state cues without taking ownership from active Home, Dashboard, AppRoot, battery, shell, map, or test lanes.

This is a **review/hardening document only**. It does not modify product behavior and it does not claim rendered contrast ratios that have not been measured from the actual iOS 27 UI.

## Evidence basis

This audit uses the product tree at `main@909b0c6f74af9744f33558d88185f3917e900c54` and specifically reviews:

- `NembraApp/Features/Home/HomeView.swift`;
- `NembraApp/Features/Home/VehicleControlsView.swift`;
- `NembraApp/Features/Dashboard/DashboardView.swift`;
- `NembraApp/Features/Dashboard/RollingSpeedValueView.swift`;
- `NembraApp/App/AppRootView.swift`;
- `NembraApp/DesignSystem/NembraVisuals.swift`;
- `scripts/ci/xcode27_simulator_capture.sh`;
- `docs/PRODUCTION_VISUAL_AUDIT_2026-08-06.md`;
- `docs/PRODUCTION_VISUAL_CAPTURE_GAPS_2026-08-06.md`.

The merged production visual audit is grounded in preserved iPhone 12 / iOS 27 Simulator screenshots and says the current systems-era UI is generally readable in the captured light/dark states. That is useful regression evidence, but it is **not** a contrast certification for current or future exact heads, and it does not cover the accessibility display settings below.

## Current Apple accessibility contract checked 2026-08-06

Current Apple Human Interface Guidelines state:

- text up to 17 pt should reach at least **4.5:1** contrast;
- 18 pt text may use **3:1**;
- bold text may use **3:1**;
- contrast must be checked in both light and dark appearances;
- system-defined colors are preferred because they provide accessible variants for appearance and Increase Contrast changes;
- color should not be the only way essential information, selection, or state is communicated.

Current SwiftUI environment contracts also expose:

- `colorSchemeContrast` — whether standard or increased contrast is active;
- `accessibilityDifferentiateWithoutColor` — when true, important state should use shape/glyph/text in addition to color;
- `accessibilityReduceTransparency` — when true, primarily transparent backgrounds should become opaque rather than relying on translucency.

References:

- https://developer.apple.com/design/human-interface-guidelines/accessibility
- https://developer.apple.com/design/human-interface-guidelines/color
- https://developer.apple.com/documentation/swiftui/environmentvalues/colorschemecontrast
- https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilitydifferentiatewithoutcolor
- https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency

These are platform contracts, not proof that Nembra currently passes every state.

## Strong current foundations

### 1. Portrait surfaces mostly use semantic system colors

Home and Ride surfaces predominantly use `.primary`, `.secondary`, `.tertiary`, `systemBackground`, and `secondarySystemBackground`. Vehicle Controls relies heavily on native `Form`, `Section`, `LabeledContent`, `Button`, and semantic foreground styles.

That is the correct default direction because system-defined colors can adapt with appearance and contrast settings. It also reduces the amount of custom color math Nembra has to own.

### 2. Major state is usually not encoded by color alone

Current source pairs most color changes with independent visible semantics:

- connection state has a text label plus icon, not just a green/orange/gray tint;
- ride mode always has visible mode text, while the marker width/opacity is presentation-only;
- lock state has text plus a lock glyph;
- Ride History continuity has text plus a glyph;
- low battery still exposes a battery glyph and numeric percentage rather than relying only on red.

This is a good base for `Differentiate Without Color`, but runtime acceptance is still required.

### 3. Dashboard primary information starts from a strong contrast architecture

The cockpit uses a black background with white primary content and keeps speed dominant. The merged visual audit already found the Dashboard readable as a functional baseline. The contrast-sensitive risk is therefore concentrated in secondary/tertiary information and translucent controls rather than the main speed number.

## Findings and risks

### P1 — accessibility display-setting coverage is currently missing

The current Simulator capture script switches light/dark appearance, but it does not enable or record:

- Increase Contrast;
- Reduce Transparency;
- Differentiate Without Color.

Therefore current exact-head visual QA can pass without exercising three settings directly relevant to the UI's semantic colors, glass surfaces, warning colors, and opacity hierarchy.

**Acceptance requirement:** the Production Visual + Performance program must add deliberate runtime evidence for these settings on iPhone 12 / iOS 27. A default-appearance screenshot is not sufficient evidence for this audit category.

### P1 — Dashboard small secondary/tertiary text needs rendered proof

`DashboardView` deliberately uses `.secondary` and `.tertiary` for small labels and supporting messages over a pure-black cockpit. Examples include:

- `MODE` and metric labels using `caption2`;
- connection supporting color;
- `Controls available when stopped` using `caption2` + `.tertiary`;
- selected/unselected stopped-mode abbreviations using white vs secondary styling.

Semantic colors are preferable to arbitrary fixed RGB values, but source code alone cannot establish the rendered contrast ratio after SwiftUI resolves the style, disabled state, glass, and accessibility settings.

The small `.tertiary` moving-controls message is the highest-risk current text treatment because it is intentionally de-emphasized and small. It should either pass the actual rendered requirement or become less visually fragile in the owning Dashboard lane.

### P1 — glass/transparency needs Reduce Transparency acceptance

`NembraGlassButtonStyle` uses iOS 26+ `glassEffect(.regular.interactive())`. Home and Dashboard also use native glass button styles in several controls. The current Nembra modifier does not itself read `accessibilityReduceTransparency`.

This audit does **not** assume Apple's glass implementation fails to adapt; it also does not assume adaptation without observing it.

**Acceptance requirement:** with Reduce Transparency enabled, verify every meaningful label/glyph/control boundary remains legible and controls remain distinguishable from their surroundings. If runtime evidence shows the system material is insufficient for a Nembra-specific composition, the eventual visual owner should add a truthful opaque/fallback treatment using the system setting rather than hard-coding a permanent heavy card.

### P1 — very-low-opacity fills and strokes must stay decorative

Home uses several low-opacity primary treatments, including approximately `0.055` fills, `0.045` strokes, and subtle shadows. Dashboard mode personality also intentionally varies ambient/marker opacity.

These values are acceptable as decoration only if structure and meaning remain understandable without perceiving those faint layers. They must not become the sole boundary that communicates:

- which control is interactive;
- which mode is selected;
- which data belong together;
- whether a state is enabled/disabled;
- warning or error meaning.

Current Home mode selection also changes text weight/foreground and is represented by the selected mode name, which helps. Final redesigned surfaces must preserve equivalent non-opacity cues.

### P1 — low-battery and connection colors require non-color acceptance

Current Dashboard uses red for low battery and green/orange/secondary for connection state. Home likewise uses connection indicator color and red battery emphasis.

The UI already carries text/glyph/numeric context, so this is not a source-level color-only failure. However, the final acceptance matrix must verify that a user with Differentiate Without Color enabled can still identify:

- low battery;
- connected vs reconnecting/offline;
- selected vs unselected ride mode;
- actionable permission/unavailable states.

Do not add fake telemetry or unnecessary alarm copy merely to satisfy this. Use existing truthful state, glyphs, labels, shape, and hierarchy.

### P1 — MapKit route strokes have a variable-background contrast problem

`RideRouteMapView` currently renders recorded route polylines using `.primary` at 4 pt over the native MapKit map. Unlike a flat system background, the map contains roads, labels, land, water, and light/dark variations chosen by the platform.

A semantic foreground style is not by itself proof that the route remains distinguishable over every map region the user may view.

**Acceptance requirement:** inspect representative light/dark route captures with urban roads, light land, dark map content, and mixed features. If contrast fails, the map owner should use an outline/casing or another MapKit-appropriate treatment that improves route separation without drawing across known route gaps or changing route truth.

### P2 — native Form/List surfaces are low custom-contrast risk but still need regression coverage

Vehicle Controls and much of Rides/Ride Details rely on native Form/List/LabeledContent semantics. That is a lower-risk contrast surface than custom glass/cockpit composition. The main regression concern is future custom styling during the Production Visual Overhaul, not a demonstrated current failure.

Keep native semantic behavior unless a deliberate redesign has runtime evidence for its replacement.

## Risk / ownership matrix

| Surface | Current contrast-sensitive treatment | Risk | Required evidence | Implementation owner boundary |
| --- | --- | --- | --- | --- |
| Home | `.secondary`, low-opacity fills/strokes, glass controls | medium | light/dark + Increase Contrast + Reduce Transparency; key error/low-battery states | active/future Home visual owner; this lane does not edit Home |
| Dashboard | white/black primary, small `.secondary/.tertiary`, red/green/orange, glass | high | moving + stopped + low battery under standard/increased contrast and Differentiate Without Color | Dashboard/battery/performance owners |
| Floating tab/shell | native iOS 27 glass | medium | light/dark + Reduce Transparency with content visible behind/near bar | shell/root owner |
| Vehicle Controls | native Form/system semantics | low | regression spot check light/dark/increased contrast | Vehicle Controls owner |
| Ride History | List/system semantics + secondary evidence text | low-medium | light/dark/increased contrast, long rows, recovered/partial evidence | Rides/accessibility owner |
| Ride Details map | `.primary` route stroke over variable MapKit content | high | representative map backgrounds light/dark; route remains distinguishable without bridging gaps | route/map integration owner |
| Future battery/range | signature instrument not yet fully landed on main | high | percent/range/unknown/learning/retained/low-battery states across contrast settings | battery/readout + eventual visual integration owner |
| Future navigation cockpit | not yet product-integrated | high | map/guidance/telemetry hierarchy under both appearance and contrast settings | navigation + Dashboard integration owner |

## Required runtime acceptance matrix

Do not mechanically multiply every screenshot by every setting. Capture the states most likely to expose a real contrast or state-cue defect.

### Baseline appearance

- Home connected/stopped — light + dark;
- Home reconnecting with retained data — light + dark;
- Home low battery;
- Dashboard moving;
- Dashboard stopped with one selected mode;
- Ride History with at least one completed/recovered state;
- Ride Details with a real recorded route.

### Increase Contrast

At minimum repeat:

- Home connected/stopped light + dark;
- Home reconnecting/error state;
- Home low battery;
- Dashboard moving;
- Dashboard stopped mode selection;
- Ride Details route/map.

Acceptance is based on the **rendered result**, not the presence of semantic color APIs in source.

### Reduce Transparency

At minimum verify:

- Home immediate glass controls;
- Dashboard stopped glass controls;
- floating iOS 27 tab chrome near content;
- any future battery/range or navigation glass surfaces.

Important text/icons and interaction boundaries must remain legible when transparent backgrounds are reduced.

### Differentiate Without Color

At minimum verify:

- connected vs reconnecting/offline;
- low-battery state;
- selected ride mode;
- lock state;
- permission/unavailable action states;
- future navigation/reroute state.

Each must remain understandable from truthful text/glyph/shape/hierarchy rather than hue alone.

## Measurement discipline

1. **Do not calculate production contrast from Swift source literals alone.** Semantic colors, materials, blur, platform appearance, accessibility contrast, disabled state, and map content resolve at runtime.
2. For stable opaque foreground/background pairs, rendered screenshots or platform-resolved colors may be measured against Apple's current ratio guidance.
3. For translucent/glass/map compositions, treat runtime screenshots and direct interaction as required evidence; a simple `foreground alpha ÷ background` estimate is not a trustworthy substitute.
4. Antialiasing edge pixels should not be sampled as if they represent the intended foreground color.
5. Record the exact app SHA, iOS 27 runtime, device type, appearance, and accessibility display settings with accepted evidence.
6. A Simulator result proves software rendering behavior for that configuration. It does not prove physical ES80 behavior and must not be described as hardware validation.

## Recommended capture-harness follow-up

When the capture/test owner has a safe lane, extend the visual acceptance harness so artifacts explicitly record whether these settings are on/off and capture a small high-value matrix for:

- standard vs increased contrast;
- transparency normal vs reduced;
- Differentiate Without Color off vs on.

Do not modify the shared capture script from this docs-only lane while other workers own CI/test/project surfaces. The important requirement is durable exact-head evidence, not a specific implementation mechanism.

## Current verdict

No source-backed catastrophic contrast defect is proven on current `main`. The existing design makes several strong choices — semantic system colors, black/white Dashboard primary hierarchy, and text/glyph companions to state color.

The release risk is that **current QA does not exercise the display-accessibility settings most likely to change the result**, while the product increasingly depends on glass, subtle secondary hierarchy, warning colors, and map overlays.

Before the mandatory Production Visual + Performance Overhaul can be called complete, Nembra needs exact-head iPhone 12 / iOS 27 evidence for Increase Contrast, Reduce Transparency, and Differentiate Without Color, with special attention to Dashboard secondary text, low-battery/connection cues, glass controls, and route-map visibility.

## Truth / hardware boundary

This audit changes no production UI, domain state, telemetry, ride evidence, route geometry, BLE/Tuya behavior, battery/range estimation, or motorized command path.

No physical AOVOPRO ES80 behavior is claimed. No physical iPhone contrast/performance result is claimed. Preserved Simulator evidence and current source are software evidence only.
