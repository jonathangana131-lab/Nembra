# Production Orientation + Safe-Area Layout Audit — 2026-08-06

Worker: `chat-y5c8n`  
Lane: `production-orientation-layout-audit`  
Base audited: `main@bf7b27d2677de94b8b275184058afca8b67fb7bc`

## Purpose

Nembra intentionally has two substantially different phone presentations: a portrait app shell and a dedicated landscape cockpit. This audit checks the boundary between them: orientation selection, state/navigation continuity, safe-area behavior, compact landscape geometry, and the acceptance evidence needed before that boundary can be considered production-ready.

This is a read-only product/source audit plus this document. It changes no Swift source, UI tests, Xcode project settings, ride truth, battery/range truth, Bluetooth behavior, or hardware state. Implementation belongs to the relevant shell/Dashboard/navigation owners after ownership clears.

## Current source contract

### Supported iPhone orientations are explicit

The app target currently declares:

- `UIInterfaceOrientationPortrait`
- `UIInterfaceOrientationLandscapeLeft`
- `UIInterfaceOrientationLandscapeRight`

and targets iPhone only (`TARGETED_DEVICE_FAMILY = 1`). Portrait upside down is not declared.

That means both landscape directions are legitimate shipping states, not test-only rotations. The product therefore needs reliable entry into landscape **and** a reliable return path to portrait.

### Root presentation is selected only by vertical size class

`AppRootView` currently does this:

```swift
if verticalSizeClass == .compact {
    DashboardView()
} else {
    PortraitRootView()
}
```

On the iPhone 12 baseline this is a compact, effective way to make ordinary landscape become the Dashboard. It is also an unconditional root replacement: compact height means Dashboard regardless of which portrait tab/detail/control screen the user was viewing before the size-class change.

### Portrait shell owns navigation/tab state inside the replaced subtree

`PortraitRootView` contains the `TabView`, both `NavigationStack` values, Home, and Ride History. Home also owns local presentation state such as the lock confirmation dialog.

Because the entire `PortraitRootView` branch disappears when the root switches to `DashboardView`, current source does not provide an explicit durable shell model for:

- selected tab;
- pushed Vehicle Controls state;
- pushed Ride Details state;
- scroll position;
- transient portrait presentation state.

SwiftUI may preserve some state in some transitions, but the source does not establish that as a product contract and current UI tests do not rotate away and back to prove it.

### Dashboard protects content from device safe areas

`DashboardView` correctly lets only the black/ambient background ignore safe areas. The content `HStack` uses horizontal and vertical `safeAreaPadding`, so the main cockpit information is not intentionally placed under the notch/home-indicator regions.

The current default landscape composition reserves fixed side rails:

- left status rail: `156 pt`;
- right context rail: `176 pt`;
- horizontal safe-area padding: `20 pt` on each side;
- center speed instrument receives the remainder.

There is no width/height breakpoint, `ViewThatFits`, scrolling fallback, or explicit compact-height alternate composition in the current Dashboard source.

### Portrait Home has an explicit floating-tab clearance workaround

Home receives `.safeAreaPadding(.bottom, 72)` because iOS 27 floating tab chrome overlays content. The merged visual-capture audit already correctly warns that `72 pt` is an implementation detail, not a universal system truth, and that Rides/detail surfaces need bottom-of-content clearance evidence of their own.

This orientation audit does not duplicate that existing shell-clearance finding. Its added concern is that the shell itself is removed in compact height and then reconstructed when returning to portrait.

## P0 product-continuity risk — rotation can replace the user's current task

The highest-value orientation issue is not cosmetic clipping. It is task continuity.

Today, rotating from portrait to compact height unconditionally swaps the full portrait shell for Dashboard. If the user is:

- browsing Ride History;
- inspecting Ride Details and a route;
- viewing Vehicle Controls;
- midway through a portrait navigation path;

landscape no longer presents that task. It presents Dashboard instead.

That can be an intentional product policy for a scooter cockpit, but the current source and tests do not define the expected return behavior. When the device returns to portrait, production acceptance must prove whether the user returns to the same tab/detail context or whether reset-to-root is an explicitly accepted interaction.

### Required production contract

Choose and encode one deliberate policy. Preferred behavior for a premium app is:

1. landscape may take over visually with the cockpit on iPhone;
2. orientation itself never changes ride/domain truth;
3. portrait navigation/tab context is retained outside the disposable portrait view subtree;
4. rotating back restores the user's previous portrait task unless another legitimate navigation event changed it;
5. sheets/dialogs that cannot safely survive a cockpit transition should dismiss intentionally rather than disappear as an accidental side effect of subtree replacement.

Do not make a view's size class the durable source of truth for selected tab, ride identity, navigation session, battery mode, or hardware command state.

## P1 layout risk — fixed Dashboard rails have little adaptation headroom

The fixed `156 + 176 pt` side rails produce a strong cockpit silhouette at the iPhone 12 baseline, and existing Dynamic Type work already flags their accessibility-size pressure. Orientation adds a separate constraint: the app has committed to **both** landscape directions and can encounter varying usable widths/heights from safe areas and system UI.

The right rail is especially dense when stopped. Four ride-mode controls at fixed `34 pt` visual frames plus spacing consume most of that rail width before considering accessibility hit geometry or future content. The rail also owns mode information and stopped vehicle controls.

The current source has no explicit fallback if the usable landscape rectangle becomes too small for all three regions.

### Required production behavior

- preserve speed as the primary cockpit information;
- preserve battery/range, connection/vehicle identity, ride context, mode, and warnings without clipping or silent disappearance;
- keep control hit targets production-accessible even if visual glyph frames remain compact;
- adapt secondary labels/rail geometry before shrinking critical values into illegibility;
- define a compact-height/width fallback before navigation/map content is integrated;
- never solve geometry pressure by converting estimated/display values into fabricated measured telemetry.

This is compatible with the merged Dynamic Type audit; it does not take ownership of those same implementation paths.

## P1 future-navigation risk — binary root swap has no cockpit rearrangement seam

The product target says navigation should integrate into Dashboard by rearranging the cockpit while keeping speed primary, expanding map/maneuver information, and restoring the normal cockpit smoothly when navigation ends.

Current `AppRootView` only distinguishes compact-height Dashboard from portrait shell. Current `DashboardView` is a fixed three-region layout with no navigation presentation input.

That is acceptable for the current systems stage, but production navigation should not be bolted on as another unrelated root replacement. The eventual shell/navigation owner should keep navigation state in a domain/application coordinator and let the Dashboard derive a presentation mode from that state.

Orientation must remain presentation context, not navigation or ride truth.

## P1 QA gap — current landscape tests prove entry, not transition continuity

`NembraUITests.swift` has valuable iPhone landscape coverage:

- moving/riding Dashboard in `.landscapeRight`;
- stopped Dashboard controls and every confirmed mode personality in `.landscapeRight`;
- touch-target assertions for stopped Dashboard controls;
- screenshots for those states.

Those tests reset the device to portrait with `defer`, but they do **not** assert app state after the return. They also do not exercise `.landscapeLeft`.

The shell capture script does not rotate at all; its direct scenario screenshots are portrait launch-state evidence. Therefore current exact-head screenshot artifacts do not prove:

- portrait → landscape → portrait task restoration;
- Rides/Details/Controls restoration across cockpit takeover;
- both landscape directions;
- safe-area equivalence left vs right around the notch;
- rotation while reconnecting/retaining vehicle data;
- rotation while an automatic ride is active/recovered;
- future navigation-active cockpit transitions.

## P2 safe-area acceptance gap — left and right landscape need equivalent evidence

Because both landscape directions ship, visual acceptance should not treat one direction as representative forever. The notch changes sides. Dashboard content currently uses safe-area padding, which is a good source-level foundation, but source inspection alone is not runtime geometry proof.

At a coherent production-visual checkpoint, capture both directions on the iPhone 12 and assert the important cockpit elements remain inside the visible safe content region. This is especially relevant for the fixed left/right rails.

Do not hard-code expected notch inset numbers into product truth. Assert relationships between the rendered controls/content and the application's safe visible region where tooling allows, and pair geometry assertions with real screenshots.

## Recommended acceptance matrix

Keep the matrix small enough to run, but include transitions rather than only cold launches.

| Start state | Transition | Required result |
| --- | --- | --- |
| Home / connected stopped | portrait → landscapeRight | Dashboard appears; confirmed vehicle state is unchanged; stopped controls remain available |
| Home / connected stopped | landscapeRight → portrait | Home returns without a fabricated reconnect or state reset |
| Rides list | portrait → landscapeRight → portrait | cockpit takeover follows chosen policy; original Rides context restores if continuity policy says retain |
| Ride Details + route | portrait → landscapeLeft → portrait | detail/navigation context restores; route evidence is unchanged and no gap is invented |
| Vehicle Controls | portrait → landscapeRight → portrait | shell context follows chosen policy; no unconfirmed command state is created |
| active automatic ride | portrait ↔ both landscapes | ride session identity/continuity remains domain-owned and unchanged by rotation |
| reconnecting / retained data | portrait ↔ landscape | retained/live distinction survives; rotation never promotes retained values to live |
| stopped Dashboard | both landscape directions | left/right rail content stays clear of safe areas; controls remain usable |
| moving Dashboard | both landscape directions | speed remains primary; stopped controls remain hidden; no geometry clipping |
| navigation active (future) | portrait/landscape transitions | same navigation session persists; cockpit rearranges/restores instead of replacing navigation truth |

For task-restoration tests, assert semantic identifiers/values before and after rotation; screenshots alone are insufficient.

## Machine-checkable regression targets

When the shell/UI-test owner has a safe implementation window, the highest-value additions are:

1. launch portrait Home, navigate to a non-root task, rotate to landscape, rotate back, and assert the expected task is restored;
2. perform the same cycle from Ride Details with a persisted route fixture and confirm the same `rides.detail` context returns;
3. run at least one stopped and one moving Dashboard test in `.landscapeLeft` in addition to existing `.landscapeRight` coverage;
4. assert the Dashboard's key rails/speed/control elements have non-empty, visible frames after each rotation and remain hittable where controls are legitimately available;
5. rotate during an active automatic-ride simulation and assert ride identity/status does not restart solely because the view tree changed;
6. once navigation lands, assert orientation changes preserve the same navigation session/generation rather than creating a new route request by presentation side effect.

These are UI/presentation regressions. Simulator fixtures remain software evidence and must never be cited as physical ES80 behavior.

## Implementation boundaries / handoff

This audit intentionally does **not** edit:

- `AppRootView.swift` — Class-A shell/navigation surface;
- `DashboardView.swift` — active Dashboard/product surface;
- `NembraUITests.swift` — frequently shared acceptance surface;
- `project.pbxproj` — Class-A project configuration.

Recommended owner order after active claims clear:

1. **Shell/navigation owner:** make portrait tab/navigation continuity explicit across cockpit takeover; decide intentional presentation dismissal behavior.
2. **Dashboard/visual owner:** establish compact landscape geometry policy before navigation/map insertion increases pressure.
3. **UI-test/acceptance owner:** add rotate-away/rotate-back continuity coverage and at least one left-landscape parity check.
4. **Navigation owner:** keep navigation session/application state outside orientation-owned views and derive cockpit presentation from it.

Avoid a parallel implementation PR while any incumbent owns those paths. This document is a handoff contract, not permission to steal them.

## Truth / hardware boundary

Orientation and safe-area changes are presentation concerns only.

This audit does not:

- verify physical AOVOPRO ES80 BLE/GATT/Tuya behavior;
- infer battery percentage source/resolution;
- create measured or estimated range;
- change speed measurement or render interpolation truth;
- create/end/recover a ride;
- create route coordinates or bridge route gaps;
- authorize any scooter write;
- prove physical-iPhone behavior from Simulator evidence.

The durable conclusion is narrower: Nembra already has a clear portrait-vs-landscape product shape and a strong safe-area foundation for the cockpit, but production acceptance still needs an explicit **rotation continuity policy**, left/right landscape parity, and an adaptive cockpit geometry seam before navigation and final visual polish can safely build on this boundary.
