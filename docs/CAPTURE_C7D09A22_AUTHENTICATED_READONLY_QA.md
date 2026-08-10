# Capture C7D09A22 — authenticated read-only QA gate

Current field procedure: `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`.

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

## Root cause / next question

The repeated approximately-30-second rejection is treated as evidence that an application-layer Tuya session was missing, not as ordinary RF instability. Do not work around it with aggressive unauthenticated CoreBluetooth reconnect loops.

The next question is whether the official Tuya SDK can establish the already-bound scooter's supported local BLE session, keep that session observably current beyond the prior rejection window, and deliver genuine application-level device updates.

## Next physical test

The next user test is **INDOOR ONLY**, stationary, and short. Do not ask for another ride yet.

1. Launch the authenticated Capture build.
2. Log in through the supported Tuya SmartLife SDK path for the user's own account.
3. Verify that the exact selected scooter device ID is present in that logged-in SDK account's owned/shared home membership.
4. Use prior physical CoreBluetooth evidence only to correlate the nearby scooter before authentication.
5. Stop Nembra's CoreBluetooth scan before Tuya takes BLE connection ownership.
6. Let `ThingSmartBLEManager` exclusively own the authenticated BLE connection.
7. Attach `ThingSmartDeviceDelegate` to the selected SDK device and observe non-empty application/DP update callbacks without publishing or querying DPs.
8. Keep the scooter stationary and untouched.
9. Keep Nembra Capture in the foreground so the monotonic local-BLE observation loop remains trustworthy.
10. PASS only if the canonical authenticated-session preflight accepts the same current connection generation: exact membership is still authorized, Tuya local BLE remains observably online for at least 45 seconds without an invalid observation gap, and at least one genuine non-empty application update belongs to that generation.
11. Export the sanitized read-only diagnostics.

No charger, wheel movement, riding, mode switching, light switching, braking, or throttle action is required for this preflight.

## Safe implementation boundary

The accepted implementation path is the official Tuya SmartLife App SDK, or another documented Tuya mechanism with equivalent authorization provenance. The field build requires the matching Tuya Developer Platform application configuration, generated security component, Bundle ID, AppKey/AppSecret, SDK initialization, authorized SDK account, and exact-device membership.

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
- verification code after use;
- access/refresh tokens;
- AppSecret;
- device/local/session keys;
- pairing tokens;
- decrypted session material.

Export may contain only non-secret evidence such as correlation identifiers, exact-device membership verdict, opaque error categories, wall-clock timestamps, monotonic session chronology, local-BLE observation state, connection generation, application-update count, sanitized opaque DP IDs/value projections, and scenario markers.

### Payload-fidelity QA

`ThingSmartDeviceDelegate` DP callbacks are application-level/decoded values. They are not raw FD50 characteristic bytes.

- The current app records only whether a structured SDK update was non-empty into the canonical session ledger.
- Diagnostic value strings are descriptive projections for offline comparison, not byte-exact/lossless payload authority.
- Do not serialize a callback to invented bytes merely to satisfy a byte-oriented API.
- Do not call a `String(describing:)` projection byte-exact, raw, or lossless.
- Do not claim `raw FD50 bytes captured` unless a separately accepted same-session authority actually produced those bytes.
- Current authenticated-preflight export must keep `rawFD50BytesCaptured = false`.

### Chronology / stale-callback QA

Each BLE attempt uses one opaque canonical connection token/generation. Same-generation callbacks may advance only that generation. Stale callbacks from a retired generation must be ignored/rejected and must not revive a failed attempt.

The 45-second gate is monotonic observed chronology, not wall-clock elapsed time. The app must reject a long foreground-observation gap before advancing liveness; a suspension/event-loop stall cannot be silently counted as continuous BLE proof.

Reconnect must discard stale attempt authority and re-establish authentication through the documented mechanism.

## Fail-closed UI behavior

Until authenticated application-data acceptance passes:

- show the exact missing Tuya SDK/account/device-membership blocker;
- offer only the short indoor authenticated preflight;
- keep full outdoor calibration disabled;
- do not claim battery/speed/power/mode mapping readiness;
- do not interpret GPS samples as scooter telemetry.

If authentication support is not configured in the build, say exactly what is missing and stop before any calibration run.

## Acceptance criteria

### PASS

All apply to one current attempt/generation:

- documented Tuya SDK authentication provenance exists;
- the exact scooter device ID is verified in the logged-in SDK account's owned/shared home membership;
- the intended physical scooter is deterministically correlated before authentication;
- Tuya SDK is the sole authenticated BLE owner;
- Tuya local-BLE status remains observably online for at least 45 monotonic seconds with no disqualifying observation gap;
- at least one non-empty `ThingSmartDeviceDelegate` application/DP update is admitted for the same current authenticated generation;
- the canonical `TuyaAuthenticatedReadOnlyPreflight` verdict is ready;
- no credential/session secret appears in export or logs;
- no DP query/publish, control, unbind, reset, or OTA action is invoked.

### FAIL

Any one of:

- no documented authorization provenance;
- exact scooter membership cannot be fully verified;
- target authority comes only from name, RSSI, or ranking score;
- guessed packet/key use;
- a second post-auth CoreBluetooth connection;
- zero current-generation SDK application updates;
- local-BLE status drops near/before acceptance;
- an observation gap is too large to prove continuous foreground liveness;
- stale-generation evidence is admitted;
- credentials/session material leak into output;
- any scooter DP query/control write;
- any unbind/reset/OTA side effect.

## What happens after PASS

Do a stationary mapping pass before any outdoor repeat:

1. untouched powered-on idle;
2. current Tuya-app battery/odometer reference recorded as operator reference only;
3. ECO / Drive / Sport local-control transitions if available;
4. light off/on local-control transitions;
5. brake held/pulses;
6. optional charger transition, indoors and skippable.

Only once authenticated application-value deltas are repeatable should Nembra label telemetry semantics. Movement/GPS calibration is the final step, not the next step.
