# Capture C7D09A22 — authenticated read-only QA gate

Current field procedure: `docs/CAPTURE_NEXT_TUYA_SECURE_LINK_TEST.md`.

## Physical truth already established

The first real field artifact is `Nembra-Scooter-Learning-C7D09A22.json`.

Accepted facts from that artifact:

- selected CoreBluetooth peripheral: `6815A5F5-4D1E-E004-BAE8-6DF924123907`;
- advertisement local name: `demo`;
- GATT service: `FD50`;
- app-to-device characteristic: `00000001-0000-1001-8001-00805F9B07D0` (`write`, `writeWithoutResponse`);
- device-to-app characteristic: `00000002-0000-1001-8001-00805F9B07D0` (`notify`);
- `17 / 17` guided scenarios completed;
- zero application characteristic payload callbacks;
- 15 peripheral-initiated disconnects at an approximately 29.93-second cadence.

The capture closed transport identification but did **not** establish speed, battery, power, mode, brake, light, lock, cruise, odometer, or other DP semantics.

## Root cause / official protocol constraint

The repeated approximately-30-second rejection is treated as evidence that an application-layer Tuya session was missing, not as ordinary RF instability. Do not work around it with aggressive unauthenticated CoreBluetooth reconnect loops.

## Next physical test

The next user test is **INDOOR ONLY** and short. Do not ask for another ride yet.

1. Launch the authenticated Capture build.
2. Authenticate through the supported Tuya SmartLife SDK path for the user's already-bound device/account.
3. Use the prior physical CoreBluetooth evidence only to correlate the nearby scooter before authentication.
4. Stop Nembra's CoreBluetooth scan before Tuya takes BLE connection ownership.
5. Let `ThingSmartBLEManager` exclusively own the authenticated BLE connection.
6. Attach `ThingSmartDeviceDelegate` to the selected SDK device and observe application/DP update callbacks without publishing or querying DPs.
7. Keep the scooter stationary and untouched.
8. Observe Tuya's documented local-BLE status for more than 45 seconds.
9. PASS only if all are true:
   - the documented SDK session succeeds;
   - Tuya reports the device locally connected continuously beyond 45 seconds; and
   - at least one non-empty genuine SDK application/DP update is received.
10. Export the sanitized read-only diagnostics.

No charger, wheel movement, riding, mode switching, light switching, braking, or throttle action is required for this preflight.

## Safe implementation boundary

The accepted implementation path is the official Tuya SmartLife App SDK, or another documented Tuya mechanism with equivalent authorization provenance. The field build requires the matching Tuya Developer Platform application configuration, generated security component, Bundle ID, AppKey/AppSecret, SDK initialization, and authorized SDK account/device session.

The fact that the user is already logged into the consumer Tuya app does **not** authorize Nembra to scrape that app's sandbox, Keychain, private files, process memory, or credentials.

### BLE ownership rule

CoreBluetooth is discovery/correlation-only for this gate. Once authentication starts, Nembra must not open a second independent CoreBluetooth connection to the scooter. A separate connection cannot be promoted as evidence from Tuya's authenticated SDK-owned session.

### Allowed protocol activity

Protocol messages internally emitted by the official/documented Tuya SDK to establish and maintain its session are allowed as SDK-owned transport authentication. Nembra does not construct, replay, expose, or reinterpret those messages as scooter commands.

After authentication succeeds, Capture remains observation-only. No DP query/publish API is exposed or invoked by this preflight.

### Explicitly forbidden

- guessed raw FD50 application/authentication packets;
- brute forcing keys, tokens, local keys, UUIDs, or counters;
- a second CoreBluetooth connection after Tuya owns authenticated BLE;
- arbitrary DP writes or queries;
- lock/unlock writes;
- speed-limit or mode writes;
- throttle, brake, regen, cruise, or light commands;
- unbind/remove-device operations;
- factory reset / pairing reset;
- OTA/firmware changes;
- extracting credentials from another app's storage or memory.

## Credential/privacy QA

Fail closed if the authorized Tuya session cannot be established.

Never write any of the following into Capture JSON, console logs, analytics, crash breadcrumbs, screenshots, Git history, or UI debug text:

- Tuya account password;
- access/refresh tokens;
- AppSecret;
- device/local/session keys;
- pairing tokens;
- decrypted session material.

Export may contain only non-secret evidence such as correlation identifiers, opaque error categories, wall-clock timestamps, monotonic session duration/chronology, local-BLE status, application-update count, sanitized opaque DP IDs/values, and scenario markers.

### Payload-fidelity QA

`ThingSmartDeviceDelegate` DP callbacks are application-level/decoded values. They are not raw FD50 characteristic bytes.

- Preserve SDK value types where practical.
- If a value must be transformed for JSON serialization, record the representation honestly.
- Do not call a `String(describing:)` projection byte-exact, raw, or lossless.
- Do not claim `raw FD50 bytes captured` unless a separately accepted same-session authority actually produced those bytes.

Reconnect must discard stale attempt authority and re-establish authentication through the documented mechanism. A failed attempt stays failed; late callbacks from that attempt must not promote it back to PASS.

## Fail-closed UI behavior

Until authenticated application-data acceptance passes:

- show `Tuya authentication required` rather than starting the 17-step calibration;
- offer only the short indoor authenticated preflight;
- keep full outdoor calibration disabled;
- do not claim battery/speed/power/mode mapping readiness;
- do not interpret GPS samples as scooter telemetry.

If authentication support is not configured in the build, say exactly what is missing and stop before any calibration run.

## Acceptance criteria

### PASS

- authorized Tuya account/device session established using a documented mechanism;
- intended scooter correlated before authentication;
- Tuya SDK is sole authenticated BLE owner;
- Tuya local-BLE status remains online for >45 seconds;
- non-empty `ThingSmartDeviceDelegate` application/DP update received from that SDK-owned session;
- no credential/session secret appears in export or logs;
- no DP query/publish, control, unbind, reset, or OTA action is invoked.

### FAIL

Any one of:

- no documented authorization provenance;
- guessed packet/key use;
- a second post-auth CoreBluetooth connection;
- zero SDK application updates;
- local-BLE status drops at/near the prior rejection window;
- credentials/session material leak into output;
- any scooter DP query/control write;
- any unbind/reset/OTA side effect.

## What happens after PASS

Do a stationary mapping pass before any outdoor repeat:

1. idle baseline;
2. current Tuya-app battery/odometer reference recorded as operator reference only;
3. ECO / Drive / Sport local-control transitions if available;
4. light off/on local-control transitions;
5. brake held/pulses;
6. optional charger transition, indoors and skippable.

Only once authenticated DP value deltas are repeatable should Nembra label telemetry semantics. Movement/GPS calibration is the final step, not the next step.
