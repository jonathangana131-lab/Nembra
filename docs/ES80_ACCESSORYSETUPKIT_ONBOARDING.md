# ES80 AccessorySetupKit onboarding research

Date: 2026-08-06
Worker: `chat-f2k7q`
Primary physical target: **2025-generation AOVOPRO ES80**

This document defines the current Apple-platform onboarding boundary Nembra should use when the real ES80 advertisement identity is known well enough to describe safely.

It is research/architecture only. It does not guess a service UUID, Bluetooth company identifier, advertised name, manufacturer-data pattern, or product image from public family clues. It does not add a production picker or motorized-hardware command path.

## Why this matters now

Current Apple Bluetooth restoration guidance for iOS 26+ makes AccessorySetupKit relevant not only to setup UX/privacy but also to later state-restoration relaunch eligibility. Nembra therefore needs an evidence-backed AccessorySetupKit plan before production background reconnect is considered complete.

The existing passive ES80 capture work is the upstream source for the physical advertisement/GATT facts this document intentionally leaves unknown.

## VERIFIED PUBLIC — current Apple contract

### AccessorySetupKit's role

AccessorySetupKit provides privacy-preserving Bluetooth/Wi-Fi accessory discovery and authorization. It owns discovery/authorization UI; after setup, app communication still uses CoreBluetooth (or NetworkExtension for Wi-Fi).

The Apple flow is conceptually:

1. declare supported accessory technology and Bluetooth discovery families in the app configuration;
2. create and activate `ASAccessorySession`;
3. create picker display items with `ASDiscoveryDescriptor` rules;
4. show the system accessory picker from a user-understandable action;
5. receive AccessorySetupKit events such as `accessoryAdded` and `pickerDidDismiss`;
6. take the authorized accessory's `bluetoothIdentifier` and use CoreBluetooth for the actual connection/protocol.

AccessorySetupKit authorization is therefore not ES80 protocol decoding and is not a command acknowledgement mechanism.

### App declaration is a safety-critical contract

For Bluetooth discovery, Apple's current documentation requires the app to declare AccessorySetupKit support and the Bluetooth families it intends to configure. Current Info.plist symbol documentation includes:

- `NSAccessorySetupSupports` with `Bluetooth` for Bluetooth/LE setup;
- `NSAccessorySetupBluetoothCompanyIdentifiers` for allowed Bluetooth company identifiers;
- `NSAccessorySetupBluetoothNames` for allowed Bluetooth device names/substrings;
- `NSAccessorySetupBluetoothServices` for allowed Bluetooth services.

Apple's current discovery guide warns that attempting Bluetooth setup discovery without the required declarations, or using identifiers/names/services that are not declared, can terminate the app.

Nembra must therefore never populate these keys from speculative ES80 family fingerprints merely to "see what appears."

#### Current Apple documentation key-name discrepancy

As of 2026-08-06, Apple's AccessorySetupKit framework/property-list symbol pages expose the support key as `NSAccessorySetupSupports`, while the narrative `Discovering and configuring accessories` guide currently spells the raw key `NSAccessorySetupKitSupports` in its prose.

Treat this as an Apple documentation inconsistency, not permission to guess. This research note uses the canonical framework/property-list symbol name `NSAccessorySetupSupports`, but a production implementation must verify the installed Xcode 27 SDK's symbol/raw generated Info.plist behavior and run the real-device setup path before acceptance. Do not hand-edit a speculative raw key based only on one prose page.

### Discovery descriptors

`ASDiscoveryDescriptor` is the system filter definition for accessories Nembra can present in the picker.

Current Apple documentation requires a Bluetooth service UUID or Bluetooth company identifier as a primary Bluetooth filter. It can also refine matching with:

- Bluetooth name substring;
- manufacturer-data blob + mask;
- service-data blob + mask;
- Bluetooth range;
- supported accessory options.

The declared app configuration and runtime descriptor must agree. A local-name substring alone is not a sufficient production identity rule.

For the ES80, Nembra should use the narrowest descriptor supported by physical capture evidence and the actual advertised fields. Public Tuya/ZYDTECH candidate UUIDs are not sufficient by themselves.

### Session/event lifecycle

`ASAccessorySession` is long-lived application setup state, not SwiftUI view-local discovery state.

After `activate(on:eventHandler:)`, the session reports events including:

- `activated`;
- `accessoryAdded`;
- `accessoryChanged`;
- `accessoryRemoved`;
- `invalidated`;
- migration completion;
- picker presentation/dismissal;
- newer discovery-filter events where supported.

When a person selects an accessory, Apple documents `accessoryAdded` before `pickerDidDismiss`. If Nembra presents its own post-setup UI, it should retain the selected `ASAccessory` until the system picker dismisses rather than racing another presentation under it.

Previously authorized accessories are available through `session.accessories` after activation.

### Authorized Bluetooth identifier

`ASAccessory.bluetoothIdentifier` is the Bluetooth UUID handle for an authorized Bluetooth accessory. Apple explicitly shows using it with `CBCentralManager.retrievePeripherals(withIdentifiers:)`, then calling CoreBluetooth `connect`.

This identifier is valuable as a local reconnect handle. Nembra must still keep these concepts separate:

- AccessorySetupKit authorization identity;
- CoreBluetooth peripheral handle;
- verified physical scooter identity for per-scooter learned range/history;
- Tuya/cloud/account identity, if any.

Do not silently treat one identifier as proof of all four semantics.

### Authorization states and removal

`ASAccessory` exposes an authorization state including `unauthorized`, `awaitingAuthorization`, and `authorized`.

`ASAccessorySession.removeAccessory(...)` removes an accessory from AccessorySetupKit management. Nembra must treat a removal event as an authorization/lifecycle change: stop assuming the peripheral remains available to the app, invalidate reconnect intent tied to that authorization, and preserve historical ride data without deleting it merely because current accessory authorization was removed.

### Custom filtered discovery

Current AccessorySetupKit also exposes picker filtering through `filterDiscoveryResults`. In that mode, AccessorySetupKit can deliver `ASDiscoveredAccessory` values with Bluetooth advertisement data and RSSI; the app may return selected `ASDiscoveredDisplayItem` values via `updatePicker(showing:)`.

This can improve presentation/filtering after Nembra has a verified base descriptor. It is **not** a loophole for unrestricted protocol research or for bypassing required Info.plist declarations.

The passive CoreBluetooth research lane remains the right place to establish raw ES80 advertisement/GATT truth before production setup rules are committed.

### Existing-accessory migration

Apple supports migration of an already-known Bluetooth accessory to AccessorySetupKit using `ASMigrationDisplayItem` and a previously known peripheral identifier.

Current Apple guidance also states that an app should **not initialize `CBCentralManager` before AccessorySetupKit migration completes**; doing so causes the migration picker flow to report an error/fail to appear. A future Nembra migration path therefore needs explicit startup ordering between AccessorySetupKit migration and the root CoreBluetooth owner.

Nembra should only build a migration path if an earlier production release legitimately managed an ES80 outside AccessorySetupKit and has a trustworthy saved peripheral handle. The current app has no reason to manufacture a migration record during research.

## DIRECT PHYSICAL / APP OBSERVATION

Current direct product evidence remains deliberately small:

- physical target is the newer Tuya-generation AOVOPRO ES80;
- its stock app exposes live battery percentage, voltage, amps/current, and watts/power.

These observations say nothing definitive about an AccessorySetupKit descriptor. They do not prove a service UUID, company identifier, manufacturer-data pattern, or advertised name is stable/unique across ES80 units or firmware.

## CORROBORATED / PROBABLE — not descriptor authority

Public research has identified Tuya and historical ZYDTECH Bluetooth-family fingerprints useful for correlation in passive capture.

Those clues may help interpret a real capture, but **must not be copied directly into**:

- `NSAccessorySetupBluetoothServices`;
- `NSAccessorySetupBluetoothCompanyIdentifiers`;
- `NSAccessorySetupBluetoothNames`;
- production `ASDiscoveryDescriptor` rules.

A production descriptor becomes acceptable only after the primary physical 2025 ES80 confirms the relevant advertised field and reasonable checks show that the rule is not dangerously broad or misleading.

## UNKNOWN / PHYSICAL VERIFICATION REQUIRED

Before production AccessorySetupKit onboarding can be implemented, capture and establish at least:

1. exact over-the-air local name(s) across repeated ES80 power cycles;
2. advertised service UUIDs and whether they are stable across sessions;
3. manufacturer identifier/data if present;
4. service data if present;
5. whether advertising materially changes between locked/unlocked/riding/charging states;
6. whether multiple nearby same-generation ES80 units remain distinguishable in the picker;
7. whether firmware/app variants use different advertised identifiers;
8. which descriptor is narrow enough for production without excluding legitimate target units;
9. whether AccessorySetupKit returns a stable/useful `bluetoothIdentifier` across app relaunch, scooter power cycle, Bluetooth toggle, and phone reboot;
10. real behavior when authorization is removed and later re-added;
11. picker presentation and setup on physical iPhone 12 / iOS 27;
12. compatibility with the production restoration/reconnect flow after setup.

## Nembra onboarding architecture

### 1. Separate setup from protocol transport

Recommended ownership:

- `AccessoryAuthorizationStore` / equivalent: AccessorySetupKit session + authorized accessory metadata;
- `ScooterBluetoothTransport`: CoreBluetooth connection/restoration/reconnect;
- ES80 protocol layer: framing/decoding only after physical evidence establishes it;
- scooter domain: truthful measured/confirmed state;
- UI: setup/reconnect presentation only.

Do not put `ASAccessorySession`, Tuya parsing, `CBCentralManager`, and Dashboard state changes into one SwiftUI object.

### 2. User-initiated picker

Apple recommends presenting enough context before `showPicker` and making setup user-initiated where possible.

Nembra should provide an explicit `Add scooter` / `Set up ES80` action. It should not surprise the rider with a system accessory picker during launch, reconnect, or a ride.

### 3. Picker presentation identity

The picker display item should use:

- an original Nembra-owned product rendering based on real ES80 hardware references;
- a clear product-facing name such as `AOVOPRO ES80` only when the descriptor is actually specific to that target;
- no invented trim/model differentiation;
- no suggestion that Nembra has verified a scooter that merely matches a broad Tuya family fingerprint.

### 4. Post-picker handoff

On `accessoryAdded`:

- retain the `ASAccessory` until picker dismissal if another sheet/onboarding step is needed;
- verify state is authorized before treating it as usable;
- persist only the legitimate non-secret identifiers needed for reconnection;
- pass `bluetoothIdentifier` to the root Bluetooth transport;
- establish a CoreBluetooth connection;
- discover/validate the verified ES80 service contract;
- only then promote connection/telemetry state.

`accessoryAdded` means authorization succeeded. It does **not** mean Nembra has decoded a valid battery packet or confirmed scooter commands.

### 5. Existing authorized accessories at launch

After `ASAccessorySession` activates:

- inspect `session.accessories`;
- do not auto-select an arbitrary first accessory if multiple are authorized;
- reconcile each authorized accessory with Nembra's local non-secret vehicle record;
- if a saved local vehicle no longer appears authorized, mark it unavailable/authorization-changed instead of silently re-pairing;
- let the production Bluetooth owner handle reconnect/restoration.

### 6. Removal and reauthorization

If AccessorySetupKit reports removal:

- cancel pending reconnect for that authorization;
- remove/disable the current CoreBluetooth authorization handle as appropriate;
- keep completed ride history and learned evidence, but do not continue attaching new evidence to an unverified replacement scooter;
- require deliberate setup before another physical scooter inherits that learned range record.

This prevents a new ES80 from silently inheriting another scooter's battery-aging/range model merely because both share the same profile.

## Descriptor acceptance gate

A proposed production ES80 descriptor must include a short evidence record:

- capture file/session ID;
- physical scooter model/firmware context where known;
- raw advertisement field used;
- repeated observations across at least several power cycles;
- whether the stock app sees the same unit under those conditions;
- collision check against other nearby Bluetooth devices / second ES80 when available;
- chosen Info.plist declaration;
- chosen `ASDiscoveryDescriptor` fields;
- reason broader candidate fields were rejected;
- physical picker result on iPhone 12/iOS 27;
- no command write required to establish the descriptor.

If that evidence is missing, the descriptor remains research-only.

## Physical acceptance matrix

Before calling AccessorySetupKit onboarding production-ready, validate on real hardware:

1. clean install with no authorized accessory;
2. user-triggered picker with one target ES80 nearby;
3. picker with target off/unavailable;
4. repeated setup after scooter power cycle;
5. two matching ES80 units nearby if feasible;
6. unrelated Tuya/other BLE devices nearby;
7. cancel picker without setup;
8. successful `accessoryAdded` then picker dismissal;
9. CoreBluetooth retrieval using returned `bluetoothIdentifier`;
10. connection + verified service rediscovery after setup;
11. app relaunch with `session.accessories` restoration;
12. screen lock/background reconnect after setup;
13. Bluetooth Settings off/on;
14. iPhone reboot + first unlock;
15. remove authorization from Nembra/system settings and observe `accessoryRemoved`/local handling;
16. re-add same physical scooter;
17. verify another scooter cannot inherit learned identity accidentally;
18. migration path only if a real prior production authorization model exists.

Record outcomes as direct physical evidence; do not promote Simulator/sample-app behavior to ES80 proof.

## Implementation dependency order

1. Land/recover the platform-neutral passive capture model.
2. Land/reconcile the CoreBluetooth passive capture adapter.
3. Capture the physical 2025 ES80 advertisement identity without writes.
4. Select the narrowest evidence-backed AccessorySetupKit declaration/descriptor.
5. Add the app configuration + AccessorySetupKit authorization service in an isolated implementation lane.
6. Integrate the returned authorized Bluetooth handle with the root restoration/reconnect transport.
7. Validate on physical iPhone 12 + ES80 before enabling production automatic hardware behavior.

This order deliberately keeps setup authorization from becoming a shortcut around protocol evidence.

## Current implementation status

**RESEARCH / ARCHITECTURE ONLY.**

This lane does not modify:

- `Nembra.xcodeproj/project.pbxproj`;
- app Info.plist/generated Info configuration;
- app bootstrap/root composition;
- `Packages/NembraBluetoothCapture`;
- ES80 passive capture model;
- command/protocol implementation;
- ride detection;
- production background Bluetooth.

## Apple sources checked 2026-08-06

- AccessorySetupKit overview: https://developer.apple.com/documentation/accessorysetupkit
- Discovering and configuring accessories: https://developer.apple.com/documentation/accessorysetupkit/discovering-and-configuring-accessories
- Setting up and authorizing a Bluetooth accessory sample: https://developer.apple.com/documentation/accessorysetupkit/setting-up-and-authorizing-a-bluetooth-accessory
- `ASAccessorySession`: https://developer.apple.com/documentation/accessorysetupkit/asaccessorysession
- `ASAccessory`: https://developer.apple.com/documentation/accessorysetupkit/asaccessory
- `ASDiscoveryDescriptor`: https://developer.apple.com/documentation/accessorysetupkit/asdiscoverydescriptor
- `filterDiscoveryResults`: https://developer.apple.com/documentation/accessorysetupkit/aspickerdisplaysettings/options-swift.struct/filterdiscoveryresults
- `ASDiscoveredAccessory`: https://developer.apple.com/documentation/accessorysetupkit/asdiscoveredaccessory
- `updatePicker(showing:)`: https://developer.apple.com/documentation/accessorysetupkit/asaccessorysession/updatepicker(showing:completionhandler:)
- `removeAccessory`: https://developer.apple.com/documentation/accessorysetupkit/asaccessorysession/removeaccessory(_:completionhandler:)
- `NSAccessorySetupSupports`: https://developer.apple.com/documentation/bundleresources/information-property-list/nsaccessorysetupsupports
- `NSAccessorySetupBluetoothCompanyIdentifiers`: https://developer.apple.com/documentation/bundleresources/information-property-list/nsaccessorysetupbluetoothcompanyidentifiers
- WWDC24 `Meet AccessorySetupKit`: https://developer.apple.com/videos/play/wwdc2024/10203/
- Nembra's separate background/reconnect contract: `docs/ES80_BACKGROUND_BLUETOOTH_RECONNECT.md`
