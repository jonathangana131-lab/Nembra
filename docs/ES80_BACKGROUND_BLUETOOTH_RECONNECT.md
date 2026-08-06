# ES80 background Bluetooth and reconnect contract

Date: 2026-08-06
Worker lane: `parallel/background-bluetooth-reconnect-research/chat-f2k7q`
Primary physical target: **2025-generation AOVOPRO ES80**

This note records the current public Apple platform contract Nembra must design around before enabling production background ES80 reconnect or automatic ride behavior.

It is intentionally separate from the passive protocol-capture work. It does **not** identify the ES80's real GATT services, data points, battery source, command semantics, or stable physical identity, and it authorizes no motorized-hardware writes.

## Evidence classification

### VERIFIED PUBLIC — Apple platform behavior

The following claims come from current Apple Developer Documentation / Apple technotes available on 2026-08-06:

1. Core Bluetooth central background execution is an explicit app capability (`UIBackgroundModes` with `bluetooth-central`). Background support lets iOS wake an eligible app for important central/peripheral delegate events, but background scanning and execution remain system-controlled rather than continuous arbitrary runtime.
2. Core Bluetooth state preservation/restoration uses a stable `CBCentralManagerOptionRestoreIdentifierKey`. The identifier must be reused across executions. For scene-based apps Apple says not to depend on `launchOptions`; recreate the manager with the stable restoration identifier and handle `centralManager(_:willRestoreState:)`.
3. Restored central state can contain peripherals that were connected or had a pending connection, plus the scan service UUIDs/options that were active.
4. Restoration/relaunch only matters while Core Bluetooth has eligible pending work and the corresponding Bluetooth event actually occurs. It is not a generic background-launch mechanism.
5. Apple's current TN3115 says a user force-quit is not a state in which Nembra may promise Bluetooth restoration relaunch. Full Bluetooth power-off in Settings also prevents restoration relaunch while Bluetooth is off. Device restart has additional first-unlock constraints.
6. TN3115 was updated for iOS 26/iPadOS 26 and says Bluetooth restoration relaunch is now tied to accessories set up with AccessorySetupKit. Nembra therefore must evaluate AccessorySetupKit for the real ES80 rather than assuming an old broad-discovery-only onboarding model will retain the same relaunch behavior.
7. `retrievePeripherals(withIdentifiers:)` returns peripherals Core Bluetooth can match to known UUID handles. `retrieveConnectedPeripherals(withServices:)` may return peripherals connected by other apps/system clients too, and Nembra still has to make its own local Core Bluetooth connection before using one.
8. `CBConnectPeripheralOptionEnableAutoReconnect` asks the system to automatically reconnect after an established peripheral link drops. Core Bluetooth reports disconnect/reconnect state through the reconnect-aware disconnect delegate callback. This is preferable to inventing a high-frequency manual retry loop when the API is available and appropriate.
9. `registerForConnectionEvents(options:)` can register for connection events matching peripheral UUIDs or service UUIDs. It is an observation/wakeup primitive, not proof that Nembra owns a usable connection and not a substitute for a local `connect` call.
10. In iOS 26 and later, Apple's current Core Bluetooth overview says an app with an instantiated `CBManager` and a Live Activity started before backgrounding can retain foreground-equivalent Bluetooth privileges for certain operations while the app remains sufficiently in use. Apple staff separately clarified in 2026 that when a locked screen turns fully off, broad/duplicate scanning restrictions can return; there is no supported workaround for continuous unrestricted scan behavior in that state.
11. Without the iOS 26 Live Activity condition, long-standing background scan restrictions remain important: duplicate advertisement discovery can be coalesced/ignored and discovery can be slower when scanning apps are backgrounded.

### DIRECT PHYSICAL / APP OBSERVATION

- The primary physical product target is the newer Tuya-generation AOVOPRO ES80.
- The stock app visibly exposes live battery percentage, voltage, amps/current, and watts/power.

These observations are correlation anchors only. They do not prove the phone-side Bluetooth transport, a stable peripheral UUID, service UUIDs, subscriptions, or restore/reconnect behavior.

### UNKNOWN / PHYSICAL VERIFICATION REQUIRED

- Whether the 2025 ES80 is eligible for a practical AccessorySetupKit setup flow and which discovery descriptor(s) correctly identify it.
- Whether its Core Bluetooth peripheral UUID remains stable enough across the real Nembra lifecycle to be useful as a reconnect handle. A Core Bluetooth UUID must not silently become the learned-range scooter identity until that stability/semantics are established.
- The ES80's real services, characteristics, notification subscriptions, and whether a useful subscription can remain pending for restoration.
- Whether the stock scooter advertises while locked, asleep, charging, recently disconnected, or after scooter-side timeout/power transitions.
- Real reconnection latency and success rates across: screen lock, app backgrounding, process eviction, process crash, Bluetooth toggles, Airplane Mode, device reboot/first unlock, scooter power cycle, range loss/re-entry, and user force-quit.
- Whether iOS restores any active/pending ES80 connection/subscription after process termination on real hardware.
- Physical iPhone 12 energy/thermal behavior for the final reconnect policy.

## Product truth rules

Nembra UI and ride logic must distinguish these states instead of collapsing them into "Bluetooth works in the background":

- `connected`: a current local Core Bluetooth link exists and required verified telemetry subscriptions/reads are usable.
- `reconnecting`: Core Bluetooth or Nembra has legitimate pending reconnect work, but usable scooter telemetry is not currently authoritative.
- `restoredPendingValidation`: Core Bluetooth restored a peripheral/pending state after process relaunch, but Nembra has not yet re-established all required verified service/characteristic/subscription invariants.
- `knownPeripheralUnavailable`: a previously authorized peripheral handle is known, but there is no current usable local connection.
- `bluetoothUnavailable`: central state is powered off, unauthorized, unsupported, resetting, or otherwise not usable.
- `backgroundLimited`: iOS lifecycle/background policy prevents Nembra from promising immediate discovery/reconnect behavior.
- `userForceQuitLimitation`: automatic relaunch/reconnect must not be promised after the user force-quits the app.

A restored `CBPeripheral` object is not itself telemetry truth. A reconnect callback is not proof that the scooter's services/characteristics are unchanged. After restoration or reconnect Nembra must validate the connection generation and the verified ES80 GATT contract before promoting live telemetry to authoritative state.

## Recommended production architecture

### 1. Long-lived central owner

The production `CBCentralManager` belongs to a root/application service whose lifetime is independent of SwiftUI screens.

Requirements:
- one stable persisted restoration identifier;
- central delegate survives view navigation/orientation changes;
- restoration is handled before normal reconnect policy mutates state;
- Core Bluetooth callbacks are serialized into a transport/domain boundary rather than directly mutating presentation;
- connection generation invalidates stale characteristic objects and stale command confirmations.

Do not copy the research-only passive capture controller into production unchanged. The capture package is intentionally foreground/research oriented and has different safety goals.

### 2. Explicit onboarding/authorization boundary

When real ES80 advertisement/service evidence is available, evaluate an AccessorySetupKit-first setup path.

Do not finalize AccessorySetupKit descriptors from a product name guess. Candidate local names/service UUIDs from public research remain fingerprints until the physical 2025 ES80 confirms them.

Persist only non-secret handles needed for legitimate reconnection. Do not use Tuya local/session secrets as a reconnect identity or learned-range identity.

### 3. Known-peripheral reacquisition order

After central state becomes `.poweredOn`, use the least speculative path first:

1. consume any state-restored peripherals/pending connection state supplied by Core Bluetooth;
2. attempt `retrievePeripherals(withIdentifiers:)` for a legitimately stored Core Bluetooth peripheral UUID handle;
3. when verified service UUIDs exist, optionally inspect `retrieveConnectedPeripherals(withServices:)` as a discovery aid, remembering that returned system-connected peers are not locally connected to Nembra yet;
4. only then perform a targeted scan using verified identity/service evidence;
5. broad scanning remains a foreground/research fallback, not the default perpetual production reconnect strategy.

Never reconnect solely because a nearby device has a familiar local-name string.

### 4. System auto-reconnect before retry storms

For an established, verified ES80 link, evaluate `CBConnectPeripheralOptionEnableAutoReconnect` on the production connection. When the callback reports the system is reconnecting, expose a truthful reconnecting state and preserve ride continuity according to RideEngine policy without manufacturing speed/battery samples.

Nembra must not schedule a rapid forever-loop of `connect` attempts. If system auto-reconnect is unavailable or unsuitable, retries need bounded backoff, lifecycle awareness, cancellation, and explicit connection-generation semantics.

### 5. Restoration validation

When `centralManager(_:willRestoreState:)` supplies peripherals:

- record that the process was restored;
- do not create a fake "connected" UI merely from the restored array;
- reattach delegates;
- inspect current peripheral connection state;
- rediscover or validate services/characteristics as required by the verified ES80 contract;
- restore notification subscriptions only when the characteristic supports and the protocol evidence requires them;
- reject stale GATT objects after service invalidation or a new connection generation;
- only then re-enable authoritative telemetry ingestion.

If restoration occurs during a ride, RideEngine continuity/provenance rules still decide whether the ride is continuous, recovered, or has an unknown transport gap. Bluetooth restoration itself must not erase an unobserved process interval.

### 6. Connection-event registration is supplemental

Once physical evidence provides a stable peripheral UUID and/or stable service UUIDs, `registerForConnectionEvents(options:)` may help Nembra observe matching peer connection events.

It must not:
- replace the local connection state machine;
- turn another app's/system connection into Nembra telemetry truth;
- bypass explicit ES80 authorization;
- use an unverified service-family guess as permanent production identity.

### 7. Background scan policy

For production automatic reconnect, prefer known/restored peripheral handles and verified service-filtered discovery over unrestricted continuous scanning.

When the app is backgrounded without a qualifying active Live Activity, assume advertisement duplicates may be coalesced and discovery may be slower. Design timeout/retry UI around that uncertainty rather than presenting a deterministic reconnect countdown.

An active ride Live Activity may legitimately improve Bluetooth privileges on iOS 26+, but Nembra must only start/maintain a Live Activity because the user has a genuine active ride/product need. It must never create a dummy activity solely to exploit background privileges.

Even with a legitimate Live Activity, do not promise unrestricted scanning while the display is fully asleep; current Apple staff guidance says restrictions can return when the locked screen turns off.

## Relaunch / lifecycle expectation matrix

This is a product expectation table, not physical ES80 validation.

| Condition | Nembra may promise automatic Bluetooth relaunch/reconnect? | Product handling |
| --- | --- | --- |
| App foreground | Yes, subject to ES80 availability/protocol | Normal local connection policy |
| App background but alive | Limited / system-controlled | `bluetooth-central`, existing connection/subscriptions, targeted reconnect |
| App suspended in memory | Event-driven only | iOS may activate for eligible Core Bluetooth events |
| Process evicted by system | Conditional | Restoration can relaunch only with eligible pending work and current iOS/AccessorySetupKit rules |
| Process crashed | Conditional | Same restoration boundary; validate restored transport before telemetry |
| User force-quit | **No promise** | Explain that automatic background reconnect may remain disabled until the user opens Nembra again |
| Bluetooth off in Settings | No while powered off | Show Bluetooth unavailable; do not spin reconnect attempts |
| Control Center Bluetooth action | Conditional/current iOS rules | Treat as platform-managed; do not promise old behavior |
| Airplane Mode | Conditional | Depends on whether Bluetooth power is actually toggled and current restoration eligibility |
| iPhone reboot | Conditional after first unlock | Recreate central with stable restore identifier; validate restored state |
| ES80 power/range loss | Conditional | Prefer system auto-reconnect + bounded policy; never fabricate telemetry during gap |

## Acceptance plan before production activation

Software implementation is not enough. Production reconnect should remain hardware-gated until this exact matrix is tested on the primary physical ES80 and an iPhone 12/iOS 27 device.

Minimum field matrix:

1. initial authorized setup and saved known-peripheral handle;
2. foreground connect / disconnect / reconnect;
3. screen lock with active telemetry subscription;
4. app background with active telemetry subscription;
5. scooter leaves range then returns;
6. scooter power off/on while app backgrounded;
7. app process eviction during pending connection;
8. deliberate process crash during pending connection;
9. Bluetooth Settings off/on;
10. Control Center Bluetooth behavior;
11. Airplane Mode with Bluetooth behavior recorded explicitly;
12. phone reboot, first unlock, then scooter availability;
13. user force-quit followed by scooter state changes;
14. active-ride Live Activity foreground/background/lock-screen behavior if that product feature exists;
15. at least one long-duration ride/reconnect energy and thermal trace on iPhone 12.

For every case record:
- iOS build and Nembra build;
- scooter firmware/app-visible identity;
- Core Bluetooth peripheral UUID handle;
- central/peripheral state transitions with monotonic timestamps;
- restoration callback presence/contents classified as transport evidence;
- service invalidation/rediscovery;
- notification resubscription result;
- time to first newly authoritative speed/battery packet after reconnect;
- whether ride provenance contains a known or unknown transport gap;
- no motorized command writes unless separately verified/authorized.

## Current implementation boundary

This lane is **research/architecture only**.

Implemented elsewhere / in flight:
- platform-neutral passive ES80 Bluetooth evidence capture;
- separate foreground Core Bluetooth passive capture adapter/research UI;
- truthful ride recovery/location/provenance foundations.

Not implemented by this note:
- production `bluetooth-central` entitlement/Info.plist wiring;
- AccessorySetupKit setup UI/descriptors;
- production root `CBCentralManager` restoration owner;
- ES80 auto-reconnect connection options;
- connection-event registration;
- background ride activation;
- physical reconnect validation.

Those should land only after dependencies and physical identity evidence are ready, without collapsing research capture and production motorized-vehicle control into one unsafe service.

## Apple sources checked 2026-08-06

- TN3115 — Bluetooth State Restoration app relaunch rules: https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules
- `CBCentralManagerOptionRestoreIdentifierKey`: https://developer.apple.com/documentation/corebluetooth/cbcentralmanageroptionrestoreidentifierkey
- Central Manager State Restoration Options: https://developer.apple.com/documentation/corebluetooth/central-manager-state-restoration-options
- Core Bluetooth overview (iOS 26+ Live Activity behavior): https://developer.apple.com/documentation/corebluetooth
- Core Bluetooth background processing guide: https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
- `retrievePeripherals(withIdentifiers:)`: https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveperipherals(withidentifiers:)
- `retrieveConnectedPeripherals(withServices:)`: https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveconnectedperipherals(withservices:)
- `CBConnectPeripheralOptionEnableAutoReconnect`: https://developer.apple.com/documentation/corebluetooth/cbconnectperipheraloptionenableautoreconnect
- `registerForConnectionEvents(options:)`: https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/registerforconnectionevents(options:)
- `CBConnectionEventMatchingOption`: https://developer.apple.com/documentation/corebluetooth/cbconnectioneventmatchingoption
- AccessorySetupKit: https://developer.apple.com/documentation/accessorysetupkit
- Apple Developer Forums, Apple staff clarification on iOS 26 background scanning + Live Activity + screen-off limits: https://developer.apple.com/forums/thread/815189
