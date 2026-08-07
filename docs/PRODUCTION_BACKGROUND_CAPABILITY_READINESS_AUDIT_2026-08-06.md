# Production Background Capability Readiness Audit — 2026-08-06

Worker: `chat-y5c8n`  
Lane: `production-background-capability-readiness-audit`  
Base audited: `main@7e73d5221192d19fbcdb7aa384510dd2044e0f1c`

## Purpose

Nembra ultimately wants automatic ride continuity, route capture, and the most automatic legitimate AOVOPRO ES80 reconnect behavior iOS permits. Those goals require background-sensitive Apple frameworks, but declaring background capabilities before the production lifecycle owners exist would create a misleading and potentially unsafe product contract.

This audit records what the shipping iPhone target **actually enables today**, what current source intentionally keeps foreground-only or disabled, and the fail-closed prerequisites for later activation.

This is an additive source/platform audit only. It does not change `project.pbxproj`, Core Location behavior, Core Bluetooth behavior, app lifecycle wiring, ride truth, or scooter commands.

## Evidence basis

Repository evidence checked on the base SHA:

- `Nembra.xcodeproj/project.pbxproj`;
- `NembraApp/App/NembraApp.swift`;
- `NembraApp/App/AppBootstrap.swift`;
- `NembraApp/App/RideLocationCapture.swift`;
- `docs/ES80_BACKGROUND_BLUETOOTH_RECONNECT.md`;
- open research PR #22 (`NembraBluetoothCapture`) for dependency/ownership context only.

Current Apple platform documentation checked 2026-08-06:

- `UIBackgroundModes`: https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes
- Handling location updates in the background: https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- `CLBackgroundActivitySession`: https://developer.apple.com/documentation/corelocation/clbackgroundactivitysession-3mzv3
- Supporting live updates in SwiftUI and Mac Catalyst apps: https://developer.apple.com/documentation/corelocation/supporting-live-updates-in-swiftui-and-mac-catalyst-apps
- `CLLocationManager.allowsBackgroundLocationUpdates`: https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates
- Core Bluetooth background processing guide: https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
- Core Bluetooth overview: https://developer.apple.com/documentation/corebluetooth

Apple documentation is the platform contract. It is not evidence that Nembra currently implements or physically validates those behaviors.

## Current target configuration — verified from source

The Nembra app target generates its Info.plist from build settings and currently declares these relevant purpose strings in both Debug and Release:

- `NSBluetoothAlwaysUsageDescription = "Connect automatically to your scooter and keep ride data in sync."`
- `NSLocationWhenInUseUsageDescription = "Map your rides while you’re riding."`

The current target does **not** declare `UIBackgroundModes` at all. Therefore current `main` does not claim either:

- `location` background execution; or
- `bluetooth-central` background execution.

The target also does not currently declare an Always-location purpose string. That is not automatically a defect: current Core Location supports explicit background activity for a when-in-use authorized app. Authorization scope must be chosen from the real product behavior rather than added speculatively.

### Important stale-prose reconciliation

Open research PR #22 still contains older prose saying the app needs an appropriate Bluetooth privacy-purpose description before physical integration. Current `main` has since added `NSBluetoothAlwaysUsageDescription`, so that particular sentence is stale.

The rest of #22's boundary remains relevant: it is a **foreground research capture package**, not the production reconnect owner, and it deliberately makes no production background reconnect claim.

## Current location implementation — foreground-only by design

`CoreLocationRideLocationSource` is explicitly documented as a foreground adapter. Its current implementation:

- creates `CLServiceSession(authorization: .whenInUse)` only when the ride-location source starts;
- consumes `CLLocationUpdate.liveUpdates(.otherNavigation)`;
- tears down the service session and async update task on stop;
- does not create or retain `CLBackgroundActivitySession`;
- does not implement an app-delegate/lifecycle restoration bridge for live Core Location updates;
- does not claim background continuation.

That matches the current project capabilities. There is no source/configuration mismatch to “fix” today.

### Current production bootstrap is even more conservative

On a normal non-Simulator launch, `AppBootstrap` currently uses `UnverifiedScooterService`, disables auto-connect, and constructs `RideApplicationStore` with `configuration: nil` and no production checkpoint/history tracking inputs.

The source comment is explicit: production ride detector and location-capture policy are not selected until real AOVOPRO ES80 timing and field-location behavior are measured.

Therefore background location is not merely missing an entitlement. The **production lifecycle that would justify it is intentionally not active yet**.

## Current SwiftUI lifecycle — no background-location restoration owner yet

`NembraApp` currently owns one `AppRuntime` in SwiftUI state and starts it from a root `.task`.

There is no current `UIApplicationDelegateAdaptor`/app-delegate bridge or equivalent Core Location background lifecycle state that recreates and resumes a live-update/background activity session after a system launch or relaunch.

Apple's current live-update guidance for SwiftUI calls for explicit lifecycle event support and long-lived state that retains the location manager/background activity session when background delivery is required.

Production background route capture should therefore not be activated by adding one Info.plist value alone.

## Apple contract relevant to Nembra

### Background location

Apple's current Core Location API supports `CLBackgroundActivitySession`, which keeps a when-in-use authorized app “in use” for an explicit background activity and allows it to receive location updates/events while that session is legitimate.

For Nembra this is a strong fit **only during a genuine active ride/navigation need**. It should not become a permanent cold-launch location session.

Current Apple guidance for background live updates also requires the app to own the lifecycle/resumption work. If the process is relaunched while a legitimate background session needs to resume, Nembra must recreate the required Core Location service/background session at the appropriate lifecycle point rather than depending on a SwiftUI view task that may never have existed in that launch path.

Older `CLLocationManager` APIs also make the configuration coupling explicit: continuous background updates require the `location` value in `UIBackgroundModes`, and enabling `allowsBackgroundLocationUpdates` without that key is fatal. Nembra's current async live-update source does not set that property, but the rule illustrates why capability activation and runtime activation must land as one coherent system rather than in unrelated PRs.

### Background Bluetooth central role

Apple's background Bluetooth central support is opt-in through `UIBackgroundModes` / `bluetooth-central`. The mode permits eligible central-role events while the app is backgrounded/suspended; it does **not** grant unlimited execution or make scanning/reconnection deterministic.

The already-merged ES80 background Bluetooth research defines the stronger product constraints Nembra must preserve:

- long-lived central manager at application lifetime;
- stable restoration identifier when state restoration is used;
- restored peripheral state is transport evidence, not telemetry truth;
- service/characteristic/subscription invariants must be revalidated after restoration/reconnect;
- user force-quit cannot be presented as automatically recoverable;
- real ES80 identity/GATT behavior remains physical-evidence gated;
- no random or speculative motorized writes.

Current `main` has no production Core Bluetooth manager to which that mode could truthfully attach. The open passive-capture package is explicitly foreground/research-only.

## P0 activation rule — capabilities follow a legitimate product owner, never precede one

Do **not** add `location` or `bluetooth-central` to the shipping target just because the final roadmap needs them.

A background mode communicates that Nembra has a real ongoing system service to perform. Turning it on while production rides, production ES80 transport, restoration policy, and lifecycle ownership are still disabled would:

- overstate current product capability;
- broaden background execution without an accepted runtime contract;
- make energy/privacy behavior harder to reason about;
- tempt later code to treat entitlement presence as evidence that background behavior is reliable;
- create App Review/user-expectation surface before the feature is ready.

The current fail-closed configuration is therefore the safer state.

## P1 background-location activation prerequisites

Before the app target declares the `location` background mode, the owning integration packet should have all of the following ready together:

1. **Production ride lifecycle selected from field evidence.** A real ES80-backed ride detector/lifecycle exists rather than `configuration: nil`.
2. **Explicit activation reason.** Background location starts only for a genuine confirmed/recovered active ride or active navigation need, not ordinary app launch.
3. **Long-lived source owner.** The location source/background activity is owned at application/domain lifetime, not by a transient Home/Dashboard/Map view.
4. **Background activity session policy.** For the async live-update architecture, create/retain/invalidate `CLBackgroundActivitySession` only for the period that legitimately needs background updates.
5. **Lifecycle restoration support.** Implement the Apple-required launch/resumption seam for SwiftUI so legitimate background Core Location work can be recreated on an eligible relaunch.
6. **Truthful gap semantics.** Any process/location interruption continues to create route/distance continuity evidence gaps; background capability never licenses interpolating a missing path.
7. **Authorization UX.** Explain why location is needed at the moment the ride/navigation feature needs it. Do not request broader authorization than the selected product behavior requires.
8. **Energy policy.** Stop high-cost navigation-grade location promptly when the ride/navigation need ends; do not keep `.otherNavigation` live indefinitely.
9. **Exact-head Simulator/software QA.** Verify launch/background/foreground state-machine behavior without calling it physical-field validation.
10. **Physical iPhone 12 ride QA.** Measure real lock/background/relaunch behavior, route gaps, energy, and thermals before claiming dependable background ride capture.

### Authorization rule

Do not mechanically add an Always-location purpose string as part of background-mode wiring.

Current Apple APIs allow a when-in-use authorized app to receive background location during a legitimate `CLBackgroundActivitySession`. If later product behavior requires starting location when the app is not already in a user-visible/in-use session, evaluate the Always authorization path separately with current Apple guidance and explicit user value.

## P1 background-Bluetooth activation prerequisites

Before the app target declares `bluetooth-central`, the owning integration packet should have:

1. a production `CBCentralManager` owner at application lifetime;
2. a verified reason to use background central events for the authorized ES80;
3. physical evidence for the ES80 identity/service/characteristic/subscription contract used by the production connection path;
4. generation invalidation so restored/stale characteristic objects cannot feed current telemetry;
5. explicit reconnect/restored-pending-validation states in the product connection model;
6. state restoration/relaunch policy aligned with current iOS behavior and AccessorySetupKit eligibility research;
7. bounded/system-assisted reconnect policy rather than a retry storm;
8. no application characteristic writes until command semantics and acknowledgements are separately verified;
9. iPhone 12 physical background/lock/range-loss/reboot/force-quit test evidence;
10. exact final-head project configuration and production transport implementation reviewed together.

The purpose string already present on main is necessary privacy disclosure for Bluetooth access, but it is not proof that background Bluetooth is implemented, reliable, or physically verified.

## P1 coupling rule — capability, runtime gate, and teardown must be reviewable together

For each background service, acceptance should be able to answer three questions from one coherent final head:

1. **Why may this start?** A truthful domain condition exists, such as a confirmed active ride/navigation session or a verified authorized scooter connection.
2. **What stays alive?** The application-lifetime owner and exact platform primitive are visible in source.
3. **What stops it?** The teardown path is deterministic when the legitimate need ends, authorization is lost, Bluetooth/location becomes unavailable, or the product state no longer justifies background work.

An entitlement-only PR cannot answer those questions and should not be treated as feature progress by itself.

## P1 production-state rules while backgrounded

Background execution must preserve the same evidence boundaries as foreground execution.

### Bluetooth

- `connected` requires a usable current local link plus required verified subscriptions/reads.
- restored peripheral objects or pending connections remain `restoredPendingValidation`/reconnecting until validation finishes.
- no new packet means no new measured speed/battery evidence.
- presentation interpolation never becomes stored telemetry.

### Location

- only accepted Core Location samples may become route coordinates;
- route gaps remain explicit across known coverage interruptions;
- no line is drawn across an unobserved gap;
- route persistence failure remains distinct from “no route recorded”;
- route geometry is never reconstructed from ODO.

### Ride lifetime

- background/foreground/rotation are presentation/lifecycle transitions, not reasons by themselves to create or end a ride;
- process restoration must recover through the accepted ride checkpoint/recovery contract;
- a background capability never proves continuity through an interval the process did not observe.

## P2 purpose-string wording needs product review when activation becomes real

The current strings are directionally consistent with the roadmap, but they should be reviewed again at the real integration head.

`NSBluetoothAlwaysUsageDescription` currently says Nembra will “Connect automatically to your scooter and keep ride data in sync.” Today production auto-connect is deliberately disabled. That is acceptable as dormant project configuration, but once Bluetooth integration is user-visible the permission copy should match the exact behavior actually shipping.

`NSLocationWhenInUseUsageDescription` says “Map your rides while you’re riding.” That aligns well with the intended user-visible active-ride purpose and should remain preferable to vague tracking language.

Do not use broader permission prose to hide implementation uncertainty.

## Required acceptance matrix before claiming background ride/reconnect support

### Location / ride

- foreground confirmed ride → lock screen → continued legitimate location session;
- foreground confirmed ride → app background → foreground return;
- process/system relaunch path while a legitimate background session needs recreation;
- location permission denied/revoked during a ride;
- location unavailable/limited accuracy and recovery;
- ride ends while backgrounded → background location session is torn down;
- route persistence failure during background capture;
- known location coverage gap → later valid coordinate starts a new segment rather than bridging;
- physical iPhone 12 long-duration ride energy/thermal observation.

### Bluetooth

Use the more detailed matrix already defined in `ES80_BACKGROUND_BLUETOOTH_RECONNECT.md`, including foreground/background, lock, range loss/re-entry, scooter power cycle, system eviction/crash, Settings Bluetooth toggle, Airplane Mode, reboot/first unlock, user force-quit, and any legitimate active-ride Live Activity behavior if that feature exists.

### Cross-domain

At minimum verify:

- Bluetooth loss while location continues does not fabricate scooter telemetry;
- location loss while Bluetooth continues does not fabricate route geometry;
- reconnect/restoration does not create a second ride identity;
- app relaunch does not automatically promote retained values to live;
- ending a ride tears down ride-only background location even if Bluetooth remains legitimately connected;
- disabling Bluetooth does not silently stop location evidence if the accepted ride policy says the ride remains recoverable through a transport gap.

## Ownership handoff

This audit intentionally does **not** edit the active/high-contention surfaces required for implementation:

- `Nembra.xcodeproj/project.pbxproj`;
- `NembraApp/App/NembraApp.swift`;
- `NembraApp/App/AppBootstrap.swift`;
- `NembraApp/App/RideLocationCapture.swift`;
- production Bluetooth service/bootstrap wiring;
- ride detector/recovery integration.

Recommended integration order after dependencies and ownership clear:

1. **Ride/location owner:** choose field-backed production ride configuration and application-lifetime location session policy.
2. **Platform lifecycle owner:** add the Core Location background activity/resumption seam required by the chosen async live-update architecture.
3. **Bluetooth transport owner:** integrate only verified ES80 transport semantics into an application-lifetime central/restoration model; keep passive research tooling isolated.
4. **Project/config owner:** add only the background modes justified by those accepted runtime owners on the same coherent integration head.
5. **Acceptance owner:** run exact-head Xcode/iPhone 12 Simulator proof plus the required physical iPhone/ES80 matrix before changing product claims.

Do not enable both background modes merely because they are eventually expected. Each mode gets its own evidence-backed activation gate.

## Current verdict

Current `main` is **correctly fail-closed** for background execution:

- privacy purpose strings exist for Bluetooth and when-in-use ride mapping;
- no background modes are declared;
- the live Core Location adapter is foreground-only and says so;
- normal production bootstrap does not yet activate ride detection/location capture;
- the research Core Bluetooth work remains foreground/passive and unwired to the production app.

The next correct step is not an entitlement-only change. It is to let physical ES80/ride evidence and the accepted production lifecycle owners mature, then activate the minimum background capabilities together with their start/restore/stop contracts and exact-head/physical acceptance evidence.

## Truth / hardware boundary

This document records source configuration and current Apple platform contracts. It does not prove:

- real AOVOPRO ES80 advertisement/GATT/DP behavior;
- physical background reconnect success;
- physical background route continuity;
- battery percentage source/resolution;
- speed cadence;
- any command acknowledgement;
- iPhone 12 energy/thermal performance.

Simulator/software evidence remains software evidence. Physical behavior remains evidence-gated.
