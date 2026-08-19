# Nembra 1.0 — selected production UI handoff

## Authority

This handoff records the user's selected production direction. It replaces the systems-era white/card-heavy prototype as the visual target for the main Nembra app. It does not reduce or defer any previously required 1.0 functionality.

The selected primary screens are:

- Home: selected Home option 2, recolored into the final warm-gold system.
- Rides: refined option 1, the contribution-style mileage archive.
- Vehicle: option 2, the energy-core composition.
- Settings: option 1, the native-quiet composition.

Reference images in this folder:

- `selected-home-gold-glass.png`
- `selected-rides-gold-glass.png`
- `selected-vehicle-gold-glass.png`
- `selected-settings-gold-glass.png`

These images define hierarchy, spatial composition, information priority, color character, and component relationships. Do not reinterpret them into a generic card dashboard.

## Visual thesis

Nembra is a near-black, premium electric-scooter interface with the quiet technical confidence of high-end EV software. Warm performance gold replaces the earlier electric blue. White is reserved for primary information, cool gray for secondary information, green only for a healthy live connection, and red only for meaningful warnings.

Core tokens:

- Nembra Gold: `#EFBC58`
- Active Gold: `#E5A83C`
- Deep Gold: `#9A5F18`
- Warm Graphite: `#0B0B0A`
- Base Black: `#060706`
- Primary Text: `#F4F7FB`
- Secondary Text: `#8D98AA`
- Healthy Connection: semantic system green
- Warning/Error: semantic system yellow/red only when truthful

Gold is an accent and luminous material response, not a full-screen theme wash. Preserve the black negative space and bright white information hierarchy.

## Native Liquid Glass contract

Use native SwiftUI/iOS Liquid Glass, not a custom stack of blur layers.

1. Prefer a standard SwiftUI `TabView` configured with the final four tabs so iOS supplies the native floating Liquid Glass tab bar. The required tabs are Home, Rides, Vehicle, and Settings. Use SF Symbols and stable tab identities.
2. If the selected dock composition requires a custom surface, group the entire dock in one `GlassEffectContainer`; use `glassEffect`, glass button styles, and a shared `@Namespace`/`glassEffectID` for the active-tab lens. Do not create a separate effect container per icon.
3. Apply interactive glass only to actual controls: dock/tab items, profile/settings buttons, compact selectors, and prominent actions. Prefer native `Toggle`, `Picker`, `Button`, toolbar, navigation, and tab components because the system automatically supplies correct Liquid Glass behavior.
4. Do not coat telemetry, graphs, battery content, list content, or every informational panel in glass. Apple's guidance treats Liquid Glass as the functional navigation/control layer above content. Use restrained standard materials and quiet surfaces in the content layer.
5. Apply `.glassEffect(...)` after layout and appearance modifiers. Use consistent shapes within a control family.
6. Use `GlassEffectContainer` for grouped effects so SwiftUI renders them together. Avoid many independent containers or effects; they can degrade performance.
7. Provide availability/fallback handling where the deployment target requires it. The target implementation and acceptance environment remains Xcode 27 with the required iOS 27 simulator/device configuration.
8. Respect Reduce Motion, Reduce Transparency, Dynamic Type, VoiceOver, contrast, and 44-point touch targets.

Apple references:

- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [Human Interface Guidelines — Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Human Interface Guidelines — Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)

## Performance and fluidity contract

- Native system components and materials take priority over custom blur/shader replicas.
- High-frequency Bluetooth/ride telemetry must not invalidate the whole tab hierarchy or glass dock. Keep live instruments in narrow observable subtrees.
- Do not animate raw telemetry or store interpolated presentation frames as measurements.
- Keep glass shapes and identities stable. Morph only real hierarchy changes and use short, interruptible system-feeling transitions.
- Do not attach continuous timelines to static glass, lists, or navigation.
- Profile on the real target simulator/device with Instruments after the visual implementation exists. Acceptance includes smooth tab changes, scrolling, mode selection, and state transitions without hitching.

## Home

The Home reference is the governing composition:

- Vehicle identity and live/last-known connection status at the top.
- Large battery percentage and estimated range with a horizontal battery body behind the scooter.
- The scooter receives studio-like depth and a grounded shadow/reflection. It is not decorative filler; it anchors vehicle identity and battery state.
- Ready/current mode, durable Today's Trip, and Today's Duration remain visible.
- Today's Trip is a calendar-day aggregate. It survives scooter power-off, Bluetooth disconnect/reconnect, app relaunch, and multiple ride sessions. It must not reset with a single ride or connection.
- Immediate Light, Lock, and Mode controls use native interactive glass and only commit visually after vehicle confirmation.
- The continuation/latest-ride row links into Rides.
- The floating four-tab dock is native Liquid Glass and remains visually stable across all primary screens.

Never fabricate range precision, connection freshness, lock state, or mode confirmation. Last-known values must be labeled as such.

## Rides

Use the refined archive reference exactly as the structure:

- Compact vehicle identity and August summary.
- One unified four-metric strip.
- Mileage Activity is the hero, using a contribution-style daily square field inspired by the user's ChatGPT activity reference.
- Tabs: Daily, Weekly, Cumulative.
- Gold intensity communicates more miles. Inactive days remain quiet graphite.
- Selecting a day reveals its date, total distance, total duration, and number of rides.
- Today's value is the durable calendar-day total across all sessions and power cycles.
- Tapping `View 2 rides` reveals the individual rides that compose the day without changing the day total.
- Preserve the calm hierarchy. Do not add unrelated route cards, fake efficiency metrics, or dashboard clutter above the activity field.

## Vehicle

Use Vehicle option 2:

- Vehicle identity and truthful connection status.
- The battery body is the dominant object: percentage and estimated range are readable at a glance.
- Ride mode is a precise Walk/Eco/Drive/Sport selector. Only scooter-confirmed state appears selected.
- Headlight, lock, cruise control, and verified speed-limit controls follow below as native rows.
- Pending, unavailable, unsupported, last-known, and confirmation-failure states need full production treatment.
- Glass belongs on interactive controls and the dock; the battery and content rails remain restrained content surfaces.

## Settings

Use Settings option 1:

- Native-quiet list hierarchy with the Nembra/vehicle identity row.
- Ride preferences: units, appearance, ride notifications, haptics.
- Data and privacy: permissions, export ride data, About Nembra.
- Use native controls and navigation. Do not turn Settings into a grid of cards.
- Permission rows must reflect actual Bluetooth/location authorization and link to the correct system recovery path.

## Work-order update

Capture remains a deliberately minimal one-time protocol utility. Finish the smallest reliable Capture workflow necessary to obtain and interpret the real Bluetooth signals, but do not allow Capture to consume the entire product effort indefinitely.

The main Nembra app must now progress too:

1. Establish the gold design tokens, four-tab architecture, and native Liquid Glass dock in production SwiftUI.
2. Implement the selected Home composition and all truthful connected/disconnected/last-known/loading/error variants.
3. Implement durable calendar-day aggregation and the selected Rides activity archive.
4. Implement the selected Vehicle energy-core surface using confirmed commands and verified profile capabilities.
5. Implement the selected native-quiet Settings hierarchy.
6. Continue into the dedicated landscape driving cockpit as a separate major design/implementation phase; do not treat portrait Home rotated sideways as the dashboard.

If hardware evidence is temporarily unavailable, continue building the real production state architecture and SwiftUI against explicit preview/test fixtures. Do not invent production telemetry and do not leave the main app frozen behind a hardware wait.

## Acceptance gate

- Build and run using GitHub-hosted/remote Macs with Xcode 27, not the user's lagging local Xcode 26 installation.
- Capture real iPhone 12/iOS 27 simulator screenshots for Home, Rides, Vehicle, Settings, and major recovery states.
- Compare them directly against these references and repeat until the composition and material behavior are product quality.
- Verify native tab-bar/glass behavior in motion; still screenshots alone cannot prove fluidity.
- Verify accessibility, reduced-motion/transparency behavior, scrolling, state confirmation, persistence, and performance.
- Do not call the result Nembra 1.0 until every promised feature is complete, fluid, polished, stable, and integrated. A runnable prototype is not the release target.
