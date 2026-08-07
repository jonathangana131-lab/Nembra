# Production Transparency + Contrast Accessibility Audit — 2026-08-06

Worker: `chat-t5m9q`
Lane: `production-transparency-contrast-audit`
Base audited: `main@3fe144ea81372564372059386c8b5a97309285d3`

## Purpose

Nembra's Production Visual + Performance Overhaul requires restrained Liquid Glass, premium native materials, clear warning hierarchy, and release-quality accessibility. This audit separates three things that are easy to conflate:

1. **native system adaptation** supplied by SwiftUI/UIKit/Liquid Glass;
2. **app-owned low-opacity/color composition** that Nembra still has to evaluate;
3. **release evidence** needed before Nembra can honestly claim sufficient contrast or color-independent state communication.

This is a Class C read-only QA/research lane plus this document. It changes no Swift, tests, Xcode project, workflow, product-memory policy, battery/range evidence, ride evidence, BLE behavior, persistence, map truth, or physical hardware state.

## Current Apple platform contract

### Reduce Transparency

Current SwiftUI exposes `EnvironmentValues.accessibilityReduceTransparency`.

Apple's contract is direct: when the preference is enabled, UI backgrounds — especially window/background surfaces — should not remain semi-transparent; they should be opaque.

Source:
https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency

This does **not** mean every decorative alpha value must become 1.0. It means translucent surfaces that carry content/legibility responsibility need an opaque-enough reduced-transparency presentation. Decorative emphasis can remain decorative only if losing/subduing it does not remove information.

### Increase Contrast

Current SwiftUI exposes `EnvironmentValues.colorSchemeContrast`. The value is `.standard` or `.increased`, follows the user's system setting, and redraws dependent views when it changes. Apps cannot override the user's choice.

Apple recommends checking it alongside `colorScheme`; if only colors/images need variants, the Asset Catalog can provide contrast-specific resources.

Sources:
https://developer.apple.com/documentation/swiftui/environmentvalues/colorschemecontrast
https://developer.apple.com/documentation/swiftui/colorschemecontrast

### Prefer system-defined colors

Apple's Human Interface Guidelines recommend system-defined colors because they have accessible variants that adapt across light/dark appearance and Increase Contrast.

Apple's current contrast guidance uses WCAG AA values as practical guidance:

- most text up to 17 pt: 4.5:1;
- 18 pt or bold text: 3:1;
- non-text state/control boundaries are commonly evaluated around 3:1.

Source:
https://developer.apple.com/design/human-interface-guidelines/accessibility/

### Differentiate Without Color Alone

Apple's current App Store accessibility criteria say common tasks must not use color as the only way to communicate selection/status/value. Text, shape, iconography, placement, or another non-color cue should accompany color.

Source:
https://developer.apple.com/help/app-store-connect/manage-app-accessibility/differentiate-without-color-alone-evaluation-criteria

### Sufficient Contrast release evaluation

Apple's current App Store criteria recommend testing common tasks with **Bold Text + Increase Contrast + Reduce Transparency**, including both light and dark appearances where applicable.

They explicitly call out translucency/blur as part of contrast evaluation and recommend testing Increase Contrast both with Reduce Transparency off and with both settings on.

Source:
https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-evaluation-criteria/

## Native Liquid Glass boundary

Current `NembraApp/DesignSystem/NembraVisuals.swift` uses native interactive Liquid Glass on iOS 26+:

```swift
.glassEffect(.regular.interactive(), in: .rect(cornerRadius: NembraMetrics.controlRadius))
```

with `.thinMaterial` only as the older-system fallback.

Apple's current Liquid Glass guidance says native Liquid Glass adapts automatically to accessibility settings such as Reduce Motion, Reduce Transparency, and Increase Contrast. The system changes material behavior/intensity rather than requiring every app to rebuild the effect manually.

Sources:
https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
https://developer.apple.com/design/human-interface-guidelines/materials
https://developer.apple.com/videos/play/wwdc2025/219/

Product implication:

- do **not** wrap every native `glassEffect` in a custom opaque replacement just because Reduce Transparency exists;
- do **not** assume native material adaptation automatically fixes Nembra-owned foreground/background alpha composition around the material;
- test the rendered control with the actual accessibility settings because custom tints, labels, fills, and neighboring surfaces can still become too subtle.

## Source audit — current main

### No current app-owned contrast/transparency environment branch

At this audit checkpoint, current app source contains no production use of:

- `accessibilityReduceTransparency`;
- `colorSchemeContrast`;
- `accessibilityDifferentiateWithoutColor`.

That is **not automatically a defect**. Nembra relies heavily on semantic system colors/backgrounds, and native SwiftUI controls/materials already adapt substantially.

The right question is whether any app-owned composition remains illegible or information-poor when those system preferences are enabled.

### Portrait Home: mostly semantic surfaces, with app-owned low-alpha decoration

Current `HomeView.swift` uses:

- `systemBackground` and `secondarySystemBackground` for major surfaces;
- `.primary`, `.secondary`, `.tertiary`, and system warning colors for text/state;
- native Liquid Glass for quick controls;
- several Nembra-owned low-alpha shapes such as `Color.primary.opacity(0.055)`, `0.10`, and a `0.045` border.

The low-alpha fills are mostly grouping/selection/depth affordances rather than the only carrier of truth. That is good, but their rendered contrast is not proven under Increase Contrast/Reduce Transparency merely because the source uses semantic `Color.primary` before applying opacity.

Current Home state does not rely on color alone for its major truths:

- connection uses both status text and a colored indicator;
- lock state uses text + lock icon;
- low battery exposes a numeric percentage and battery-level symbol in addition to red emphasis;
- selected ride mode uses text/selection shape/weight, not only hue;
- errors/recovery use explicit text and distinct symbols.

The incumbent production Home owner is PR #70. This audit must not implement a competing Home style policy.

### Landscape Dashboard: intentionally dark, with very low-opacity personality decoration

Current `DashboardView.swift` fixes the cockpit to dark appearance with `.preferredColorScheme(.dark)` and renders white/semantic foregrounds on black.

Truth-bearing cues are generally redundant with color:

- connection has text + a state-specific symbol + semantic color;
- battery displays percentage + battery symbol; low battery adds red emphasis;
- ride mode is written as text, while its marker/scale/ambient intensity are presentation-only;
- stopped controls use symbols/text and confirmed state, not color-only inference.

The main contrast risk is **not** the black cockpit base. It is app-owned subtle personality/depth decoration:

- ambient radial gradient opacity ranges roughly `0.012...0.062`;
- mode marker opacity ranges roughly `0.14...0.62`;
- selected mode background uses white at `0.12` opacity;
- secondary/tertiary status text is intentionally quiet.

Those effects are designed to be subordinate, and mode identity remains explicit text even if the decoration disappears. That makes them safer than color-only telemetry, but the final visual pass must still prove that important controls/labels maintain sufficient contrast under Increase Contrast.

PR #33 owns current Dashboard high-frequency performance work and PR #57 owns the Dashboard battery primary-readout integration. This lane does not modify their files.

### Ride status/history/details: system-first composition

Current `AppRootView.swift` uses system `TabView`, `NavigationStack`, `List`, `Form`-style rows, system backgrounds, standard labels, and semantic foreground styles for the Ride surfaces.

Ride status/error communication is not color-only:

- failures pair red with an `exclamationmark.triangle.fill` symbol and explicit status text;
- temporary disconnect uses a distinct reconnect symbol;
- active/candidate ride states use a location symbol and accessible text;
- completed/recovered ride rows use different symbols and explicit continuity text;
- route availability/error states use labels and explanatory text.

This is a strong color-independence baseline.

The Ride map polyline currently uses `.primary` rather than a hard-coded color, which is preferable for system adaptation. Final route/map acceptance still needs actual rendered contrast checks against the MapKit basemap in the supported state matrix.

### Vehicle Controls: almost entirely native semantic UI

Current `VehicleControlsView.swift` is a `Form` with native sections, buttons, labels, progress indicators, and checkmarks. Selected choices are communicated by checkmark state, not color alone.

No custom material or low-alpha composition was found in this surface at current main. It should still be included in release accessibility verification because platform appearance changes can expose layout/legibility issues, but it is not a current custom-transparency hotspot.

### Legacy scooter artwork file is not a current common-task dependency

`VehicleHeroView.swift` contains extensive custom opacity artwork and a `.thinMaterial` lock badge, but no current `VehicleHeroView(...)` call site was found in the audited app composition.

Therefore its decorative alpha values are not treated as a current common-task release blocker. If the production visual overhaul reintroduces this or similar artwork, it must be re-audited because decorative opacity, red/yellow detail, and translucent material could become visible product surfaces again.

## Current capture/test gap

Direct inspection of `scripts/ci/xcode27_simulator_capture.sh` shows that the production capture gate:

- creates/boots an iOS 27 Simulator;
- prefers iPhone 12;
- runs the full test bundle;
- installs the app;
- normalizes the status bar;
- captures the named light/dark simulation scenarios.

It does **not** enable, verify, or record:

- Increase Contrast;
- Reduce Transparency;
- Bold Text;
- Differentiate Without Color;
- Smart Invert or other accessibility display variants.

Current production screenshots therefore cannot prove sufficient contrast or color-independent behavior under those settings.

This is an **acceptance gap**, not evidence that the current UI fails those settings.

## Supported interactive acceptance path

Apple documents Xcode Environment Overrides for changing a running app's appearance and accessibility environment during debugging. The documented Accessibility override set includes options such as **Increase Contrast**.

Source:
https://developer.apple.com/documentation/xcode/diagnosing-issues-in-the-appearance-of-your-running-app

Use that as a fast supported iteration tool where the desired override is exposed, but final release confidence should also exercise the actual iOS 27 system settings on the Simulator.

Do not invent or trust undocumented `simctl defaults write` commands as release proof without first validating them against the exact Xcode 27/iOS 27 runtime.

## Required production acceptance matrix

At a coherent visual/accessibility release checkpoint, exercise common tasks on the real iPhone 12 / iOS 27 Simulator candidate.

| State | Standard | Increase Contrast | Reduce Transparency | Increase Contrast + Reduce Transparency | Truth / interaction check |
| --- | --- | --- | --- | --- | --- |
| Home connected stopped | light + dark | yes | yes | yes | identity, battery, trip, mode, controls remain readable |
| Home low battery | light + dark where material | yes | yes | yes | low battery remains clear without relying on red alone |
| Home reconnect/error | key states | yes | yes | yes | stale/recovery/error hierarchy remains legible |
| Dashboard stopped | dark | yes | yes | yes | mode/control selection boundaries remain readable |
| Dashboard moving | dark | yes | yes | yes | speed stays dominant; secondary rail text remains legible |
| Dashboard low battery | dark | yes | yes | yes | warning remains clear via symbol/value as well as red |
| battery `% ↔ range` | once integrated | yes | yes | yes | selected/readout state remains identifiable and truthful |
| Ride History / Details | light + dark | yes | yes | yes | evidence labels/route status remain readable |
| route map | relevant route states | yes | yes | yes | real route line remains distinguishable from basemap |
| Vehicle Controls | light + dark | yes | yes | yes | selected/pending/disabled choices stay recognizable |

Also run **Differentiate Without Color** across common tasks once final styling stabilizes, even where current source already has redundant labels/icons. The release criterion is the finished common-task experience, not a source-code checkbox.

## Contrast measurement guidance

Use Xcode Accessibility Inspector or another accepted contrast checker on the actual rendered candidate where automated/system analysis is meaningful.

Prioritize measurements for:

- small secondary/tertiary text on dark Dashboard;
- selected vs unselected custom mode controls;
- custom low-alpha control/group boundaries when they are necessary to recognize interactivity;
- warning text/iconography;
- route overlay against MapKit basemap;
- text placed near/over native Liquid Glass after material adaptation.

Do not demand a contrast ratio for purely decorative ambient light that communicates no state. Instead verify that removing/subduing that decoration does not remove meaning.

## Native adaptation vs custom fallback decision rule

For each final surface:

1. prefer semantic system colors/backgrounds/materials first;
2. test the real rendered state with Increase Contrast/Reduce Transparency;
3. if native adaptation already yields sufficient legibility, do not add redundant custom branches;
4. if a Nembra-owned translucent surface still carries required content and remains too transparent, use `accessibilityReduceTransparency` to provide an opaque-enough alternative;
5. if custom colors/fills remain too subtle under increased contrast, use `colorSchemeContrast` or contrast-specific assets/tokens to strengthen the required boundary;
6. if meaning still depends on hue, add text/icon/shape/placement — do not solve color blindness by merely making the hue more saturated;
7. keep telemetry, command confirmation, battery evidence, ride evidence, and route truth identical across accessibility presentations.

## Active-worker boundaries

At this audit checkpoint, implementation ownership remains with existing lanes, including:

- PR #70 — Home vehicle-status hierarchy;
- PR #57 — Dashboard battery primary readout;
- PR #33 — Dashboard high-frequency performance;
- PR #67 — shell/tab clearance;
- PR #75 — dependent Ride History row accessibility;
- PR #41/#77 — navigation core/MapKit adapter;
- PR #45 — battery presentation-transition semantics.

This audit should inform those owners/integration work after dependencies settle. It must not justify parallel edits to their product files.

## Release-claim boundary

Do **not** mark App Store accessibility support for Sufficient Contrast or Differentiate Without Color Alone based only on:

- semantic-color usage in source;
- native Liquid Glass documentation;
- one normal-motion/light-mode screenshot;
- this audit.

Apple's current criteria are common-task criteria and should be re-evaluated after each meaningful visual change.

Nembra can only make those release claims after the final exact release candidate's common tasks are tested with the relevant system settings and any app-owned weak boundaries are fixed.

## Truth / hardware boundary

Transparency, contrast, and color differentiation are presentation/accessibility behavior only.

This audit does not:

- reclassify measured/estimated/display battery evidence;
- change range learning;
- change speed measurement/interpolation evidence;
- alter ride lifecycle or route geometry;
- send BLE/Tuya reads/writes;
- establish physical AOVOPRO ES80 behavior;
- claim physical iPhone performance or physical-device accessibility proof.

Simulator/source/public Apple evidence remains distinct from physical scooter validation.

## Acceptance conclusion

Current Nembra has a **strong system-first accessibility foundation**: semantic backgrounds/colors dominate common-task UI, status meaning is usually backed by text/icon/number rather than color alone, and native Liquid Glass carries built-in system accessibility adaptation.

The production risk is more specific:

- several custom low-alpha fills/markers/ambient effects have not been visually accepted under increased contrast;
- the capture pipeline does not exercise Increase Contrast/Reduce Transparency/Bold Text/color-differentiation settings;
- future signature battery/navigation/Liquid-Glass choreography can introduce new foreground/material combinations that must be re-tested.

Do not add blanket opacity overrides now. Expand final acceptance around the real system settings, measure actual weak boundaries, and add targeted app-owned fallbacks only where native adaptation is insufficient.
