# Production Authorization + Permission UX Audit — 2026-08-06

Worker: `chat-y5c8n`  
Lane: `production-authorization-permission-ux-audit`  
Base audited: `main@9ef56ff6911a9a5d1a7492ed4a47c9163a9130a8`

## Purpose

Nembra eventually needs two protected system resources for its primary product loop:

- Bluetooth, to connect to a verified AOVOPRO ES80;
- location, to map and quality-screen real rides/navigation.

The app already has important fail-closed foundations, but the production authorization UX is intentionally incomplete because the real ES80 transport and production ride/location lifecycle are not active yet. This audit defines the user-facing authorization contract that must exist **before** those systems are enabled.

This is a source/platform audit only. It changes no Swift, project configuration, privacy prompt, Core Location/Core Bluetooth behavior, telemetry, ride state, or scooter command path.

## Evidence basis

Repository source checked on the base SHA:

- `Nembra.xcodeproj/project.pbxproj`;
- `Packages/NembraCore/Sources/NembraCore/VehicleDomain.swift`;
- `NembraApp/App/RideLocationCapture.swift`;
- `NembraApp/App/RideApplicationStore.swift`;
- `NembraApp/App/AppBootstrap.swift`;
- `NembraApp/Features/Home/HomeView.swift`;
- merged `docs/PRODUCTION_BACKGROUND_CAPABILITY_READINESS_AUDIT_2026-08-06.md`;
- foreground ES80 research boundaries for future Bluetooth integration.

Current Apple guidance checked 2026-08-06:

- Requesting authorization to use location services: https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services
- Suspending authorization requests (`CLServiceSession`): https://developer.apple.com/documentation/corelocation/suspending-authorization-requests
- Core Location authorization status: https://developer.apple.com/documentation/corelocation/clauthorizationstatus
- Temporary full-accuracy authorization: https://developer.apple.com/documentation/corelocation/cllocationmanager/requesttemporaryfullaccuracyauthorization(withpurposekey:)
- `CBManager.authorization`: https://developer.apple.com/documentation/corebluetooth/cbmanager/authorization-swift.type.property
- `CBManagerAuthorization`: https://developer.apple.com/documentation/corebluetooth/cbmanagerauthorization
- Apple HIG privacy guidance: https://developer.apple.com/design/human-interface-guidelines/privacy

Apple platform documentation is platform evidence, not physical ES80 validation.

## Current state — Bluetooth recovery UX is already substantially modeled

`VehicleConnectionIssue` already distinguishes:

- `bluetoothPoweredOff`;
- `bluetoothPermissionDenied`;
- `scooterUnavailable`;
- `unsupportedConfiguration`.

`HomeView` already turns those connection issues into distinct recovery presentations. In particular, `.bluetoothPermissionDenied` produces a clear “Bluetooth access is off” message and an app-Settings action via `UIApplication.openSettingsURLString`.

That is a strong production pattern worth preserving:

- connection authorization is represented as connection state/issue, not fake telemetry;
- denied access blocks connection attempts;
- retained vehicle values stay separate from a current confirmed connection;
- recovery action is visible at the surface where the missing permission prevents the user's goal.

The production Bluetooth adapter is not yet active, so this UI is a contract/foundation rather than physical ES80 proof.

## P1 Bluetooth gap — `restricted` is not the same as `denied`

Apple's current `CBManagerAuthorization` has separate states for:

- `.notDetermined`;
- `.allowedAlways`;
- `.denied`;
- `.restricted`.

Apple explicitly documents `.restricted` as a state the user may be unable to change, for example because of active restrictions such as parental controls.

Nembra's current public vehicle connection issue model has only `bluetoothPermissionDenied`. Its Home recovery copy tells the user to allow Bluetooth in Settings.

That copy is correct for a normal app-level denial, but it would be misleading if a future production adapter collapses `.restricted` into the same issue: the Settings button may not offer a fix.

### Integration requirement

Before real Core Bluetooth wiring lands, preserve the distinction somewhere in the application/presentation model. A reasonable user contract is:

- **not determined:** initiate the protected-resource flow only after the user asks to connect/use the scooter feature;
- **allowed:** continue normal connection validation;
- **denied:** show the existing Settings recovery affordance;
- **restricted:** explain that Bluetooth access is restricted and may need device/parental-control policy changes; do not promise that opening Nembra Settings will fix it;
- **powered off / unavailable:** remain a separate transport condition from authorization.

Do not turn authorization into `.scooterUnavailable`, and do not treat Bluetooth permission as evidence that an ES80 exists or is connected.

## Current state — location diagnostics are truthful but not yet user-facing

`CoreLocationRideLocationSource` already maps Apple's live-update diagnostics into explicit internal cases:

- `authorizationRequestInProgress`;
- `authorizationDenied`;
- `authorizationDeniedGlobally`;
- `authorizationRestricted`;
- `accuracyLimited`;
- `insufficientlyInUse`;
- `locationUnavailable`;
- `serviceSessionRequired`;
- `invalidLocation`;
- `streamFailed`.

That is a strong evidence boundary. The capture coordinator treats an explicit issue as a coverage discontinuity and never fabricates a coordinate to fill it.

However, `RideLocationCaptureCoordinator.consume(_:)` currently consumes the issue only for route/GPS continuity handling. It does not expose a durable application-level authorization/availability state that Home, Dashboard, Rides, or navigation can explain to the user.

That is acceptable today because normal production bootstrap does not enable the production ride/location lifecycle. It becomes a product gap the moment real automatic ride mapping/navigation is enabled.

## P0 location requirement — permission state must not disappear inside the evidence pipeline

When production ride/location becomes active, authorization state needs two consumers with different jobs:

1. **Evidence pipeline:** stay conservative. Authorization/availability interruptions keep marking route coverage gaps and rejecting unsupported coordinates exactly as required by the ride truth model.
2. **Presentation/application state:** explain why mapping/navigation is unavailable or degraded and what the user can legitimately do next.

Do not “fix” the missing UX by removing issue-to-gap behavior or by promoting reduced/retained data into measured route truth.

A denied location permission can coexist with a valid scooter ride. Nembra should be able to say, in effect, “ride tracking is continuing with available evidence; map/GPS coverage is unavailable” rather than ending the ride or inventing route geometry.

## Apple permission timing — just in time, not cold launch

Apple's current privacy guidance recommends requesting protected-resource access only when the user engages a feature that clearly needs it. Core Location guidance specifically warns that launch-time requests can be misinterpreted and denied.

Nembra's current location adapter is already aligned with that direction: it creates `CLServiceSession(authorization: .whenInUse)` only when the ride-location source starts, and its source comment explicitly rejects surprise cold-launch prompting.

Preserve that behavior when production lifecycle wiring arrives.

### Bluetooth

Do not construct the production permission flow merely to obtain an authorization answer at ordinary cold launch. The user-visible trigger should be a legitimate scooter connection/setup/reconnect flow, while the application-lifetime central manager design remains consistent with Apple's actual Core Bluetooth lifecycle requirements.

### Location

The first authorization request should be causally tied to a real mapping/navigation/ride-location need. If automatic ride detection starts without location authorization, the product needs a deliberate policy for when it is appropriate to ask rather than allowing an unexplained system alert to appear after movement begins.

The system alert's purpose string is not a substitute for an in-product explanation when the timing would otherwise be surprising.

## P1 first-run automatic-ride tension — decide the prompt seam before enabling production rides

Nembra's desired ride behavior is automatic: the user should not normally press “Start Ride.” That creates a permission-design tension for first-time location access.

A production implementation should not wait until an already-moving automatic ride has silently begun and then unexpectedly interrupt the rider with a location authorization alert.

Before enabling the real automatic ride detector, choose a deliberate first-use seam such as:

- an explicit “Enable ride maps” / vehicle setup step after the user has connected their scooter and the value is clear;
- an onboarding explanation followed by a deferred `CLServiceSession` prompt when the user elects to enable ride mapping;
- another user-initiated mapping/navigation affordance that clearly explains future automatic ride-map behavior.

The exact UI belongs to the product/shell owner. The invariant is that automatic domain behavior must not produce a surprising protected-resource prompt at a physically distracting moment.

Do not add a manual Start Ride button merely to solve authorization timing.

## P1 denied/restricted recovery matrix

| Resource state | Product meaning | Correct user action | Truth behavior |
| --- | --- | --- | --- |
| Bluetooth `.notDetermined` | permission choice not made | request only from legitimate scooter-use flow | no connection/telemetry claimed yet |
| Bluetooth denied | app access denied | explain + open app Settings | remain disconnected; retained values remain retained |
| Bluetooth restricted | access unavailable by policy | explain restriction; don't promise Settings fixes it | remain disconnected; no retry storm |
| Bluetooth powered off | radio/system availability issue | explain Bluetooth is off | remain disconnected/reconnecting according to transport contract |
| Location request in progress | system choice unresolved | show non-alarming pending/degraded mapping state if needed | no missing coordinate invented |
| Location app-level denied | Nembra can't use location | explain ride can continue without map/GPS evidence; offer Settings recovery where appropriate | route/GPS gap remains explicit |
| Location denied globally | Location Services disabled globally | explain system-level cause separately from app denial | route/GPS gap remains explicit |
| Location restricted | user may not be able to change access normally | explain restriction; don't imply ordinary app toggle is guaranteed | route/GPS gap remains explicit |
| Reduced/limited accuracy | location exists but precision is limited | explain only if it materially affects feature; don't nag | quality screen remains authority for accepting coordinates |
| Location temporarily unavailable | transient platform condition | no permission blame; recover automatically if possible | gap/quality semantics remain conservative |

## P1 reduced accuracy is not equivalent to “permission denied”

`CLLocationUpdate` can report `accuracyLimited` while still providing a location. Current Nembra source intentionally carries both the sample and the issue into its evidence layer.

That distinction should remain visible to future UX design:

- reduced accuracy is not “location off”;
- a sample still must pass `RideLocationQualityScreen` before it can become durable route/distance evidence;
- the app should not demand Precise Location solely to make a warning disappear;
- if real field evidence later shows full accuracy is necessary for a specific feature, use Apple's temporary full-accuracy mechanism only with a specific configured purpose key and a user-visible reason.

Current project configuration does not declare a temporary full-accuracy purpose dictionary, and this audit does not recommend adding one speculatively.

## P1 distinguish authorization from service availability

Both platform domains have multiple failure causes that must not collapse into one generic “permission” banner.

Bluetooth examples:

- user denied access;
- access restricted by policy;
- Bluetooth powered off;
- scooter absent/out of range;
- ES80 configuration not yet verified.

Location examples:

- authorization denied;
- authorization denied globally;
- authorization restricted;
- request still in progress;
- service session/lifecycle requirement not met;
- temporary location unavailable;
- reduced accuracy;
- bad concrete sample.

This matters because the recovery action differs. A Settings button attached to every failure is not truthful UX.

## P1 application model recommendation — expose capability state, not raw framework objects

Do not make SwiftUI screens own `CLLocationManager`, `CLServiceSession`, or `CBCentralManager` just so they can render a permission banner.

The eventual application-lifetime owners should publish small canonical capability/presentation state derived from platform state. Screens can then render actions without owning platform lifecycle.

For location, the application-facing state should be able to express at least:

- not requested / disabled by product policy;
- authorization request in progress;
- available for the current legitimate ride/navigation use;
- denied by the user;
- globally disabled;
- restricted;
- temporarily unavailable;
- reduced accuracy / degraded quality where product-relevant.

For Bluetooth, extend or map the existing `VehicleConnectionIssue` contract so restricted vs denied remains truthful.

These states are **availability/presentation evidence**, not scooter telemetry and not ride-history measurements.

## P1 retry and Settings behavior

Opening Settings is a recovery affordance, not a retry loop.

When the app becomes active again after the user visits Settings:

- re-read the authoritative platform authorization/availability state;
- let the long-lived owner decide whether a legitimate pending connection/location need should resume;
- do not assume the setting changed merely because the app foregrounded;
- do not promote retained vehicle data to live while authorization is still denied;
- do not bridge a route gap merely because permission returned;
- do not repeatedly re-present the system authorization prompt after an app-level denial.

Apple stores the user's authorization choice and allows later changes through system settings; Nembra should react to the actual new state rather than its prior button tap.

## P2 purpose-string copy should match the shipping feature at activation time

The current generated Info.plist uses:

- Bluetooth: “Connect automatically to your scooter and keep ride data in sync.”
- Location: “Map your rides while you’re riding.”

The location string is narrow and maps well to the intended user value.

The Bluetooth string describes future automatic connection behavior while production auto-connect is currently deliberately disabled. Before the real ES80 connection path ships, review this copy against the exact behavior being enabled. A purpose string should explain the protected resource's use, not make a reliability promise that physical integration has not yet proven.

Do not broaden either string to hide uncertainty.

## P2 accessibility + interaction requirements

Permission/degraded-state recovery UI must follow the same production accessibility contract as other Nembra state:

- VoiceOver announces the cause and available recovery action, not only an icon/color;
- Settings/retry controls have stable labels and appropriate hit targets;
- Dynamic Type does not truncate the recovery explanation into ambiguity;
- Reduce Motion does not hide the state transition;
- permission state changes are not spammed as repeated announcements while a platform request is still in progress;
- the app preserves the user's current ride/navigation context when returning from Settings.

## Required acceptance matrix before production authorization is considered complete

### Bluetooth

- first connection attempt with authorization not determined;
- allowed access;
- app-level denied access;
- restricted access;
- Bluetooth powered off with permission otherwise allowed;
- Settings round-trip with no setting changed;
- Settings round-trip after access is restored;
- access revoked while previously connected;
- reconnect after restored access without retained-data promotion;
- physical iPhone 12 + real ES80 verification for actual prompt/connection behavior.

### Location

- first intentional ride-map enable flow while not determined;
- allow once / when-in-use behavior as applicable to selected API path;
- app-level denial;
- global Location Services denial;
- restricted state;
- reduced-accuracy state with both an acceptable and unacceptable concrete sample;
- Settings round-trip with and without a changed authorization;
- authorization revoked during an active ride;
- authorization restored during the same ride: next accepted point starts after the known gap rather than drawing across it;
- location unavailable without any authorization change;
- future background-activity activation only after #104's separate background readiness gates are met.

### Cross-domain

- Bluetooth denied while location remains available: no scooter telemetry, but legitimate location evidence remains independent;
- location denied while Bluetooth remains connected: scooter ride evidence may remain valid, but map/GPS coverage is explicitly incomplete;
- both denied: app remains understandable and recoverable rather than reporting generic connection failure;
- Settings return does not restart or duplicate an active/recovered ride solely because the scene became active.

Simulator fixtures may validate software presentation/state machines. They are not physical ES80 permission/transport evidence.

## Ownership handoff

This audit intentionally does **not** modify active/high-contention paths:

- `Packages/NembraCore/Sources/NembraCore/VehicleDomain.swift`;
- `NembraApp/Features/Home/HomeView.swift`;
- `NembraApp/App/AppBootstrap.swift`;
- `NembraApp/App/RideLocationCapture.swift`;
- `NembraApp/App/RideApplicationStore.swift`;
- `Nembra.xcodeproj/project.pbxproj`;
- production Core Bluetooth integration.

Recommended owner sequence when dependencies are ready:

1. **Production Bluetooth owner:** map `CBManager.authorization` and manager state into truthful connection issues, including restricted vs denied, without claiming ES80 identity before validation.
2. **Ride/location lifecycle owner:** surface `RideLocationSourceIssue`/authorization availability to application state while preserving issue-to-gap evidence semantics.
3. **Product/shell owner:** implement just-in-time first-use explanation and denied/restricted recovery surfaces at a non-distracting point in automatic ride-map onboarding.
4. **Project/config owner:** review purpose strings and any temporary-accuracy/background keys only when the corresponding runtime behavior actually ships.
5. **Acceptance owner:** cover permission state machines on exact final code and then verify real prompts/Settings/recovery on physical iPhone 12; real ES80 behavior remains separately hardware-gated.

## Current verdict

Nembra does **not** need a broad permission rewrite today.

The current state is appropriately conservative:

- production ES80 transport and production ride location remain disabled/unverified;
- Bluetooth denied-recovery UI already has a strong truthful foundation;
- Core Location already carries granular diagnostics and turns interruptions into evidence gaps;
- the app avoids cold-launch location prompting.

The remaining production contract is precise:

- preserve Bluetooth `restricted` vs `denied` truth;
- expose location authorization/availability to users instead of leaving it only inside the evidence pipeline;
- choose a deliberate, non-distracting first-use permission seam compatible with automatic rides;
- treat reduced accuracy, global disablement, restriction, temporary unavailability, and app denial as different states;
- react to actual state after Settings rather than assuming recovery;
- never let permission UX manufacture scooter telemetry, ride continuity, or route geometry.

## Truth / hardware boundary

This audit does not verify:

- physical AOVOPRO ES80 BLE identity/GATT/Tuya behavior;
- real iPhone Bluetooth authorization prompt timing for the future production adapter;
- physical reconnect success;
- physical location precision/energy behavior;
- ES80 speed/battery cadence;
- any scooter command acknowledgement.

All physical behavior remains evidence-gated.
