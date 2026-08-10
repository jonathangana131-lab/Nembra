# Capture C7D09A22 — authenticated read-only QA gate

## Physical truth already established

The first real field artifact is `Nembra-Scooter-Learning-C7D09A22.json`.

Accepted facts from that artifact:

- selected CoreBluetooth peripheral: `6815A5F5-4D1E-E004-BAE8-6DF924123907`
- advertisement local name: `demo`
- GATT service: `FD50`
- app-to-device characteristic: `00000001-0000-1001-8001-00805F9B07D0` (`write`, `writeWithoutResponse`)
- device-to-app characteristic: `00000002-0000-1001-8001-00805F9B07D0` (`notify`)
- 17 / 17 guided scenarios completed
- zero application characteristic payload callbacks
- 15 peripheral-initiated disconnects at an approximately 29.93 second cadence

The capture therefore closed transport identification but did **not** establish speed, battery, power, mode, brake, light, lock, cruise, odometer, or other DP semantics.

## Root cause / official protocol constraint

Tuya documents `FD50` as its application-layer Bluetooth pairing/data service. Tuya also documents a 30-second illegal-connection removal path when the expected application-layer pairing/authentication exchange does not complete. The physical ~29.93 second cadence is consistent with that documented behavior.

This is no longer treated as ordinary RF instability and should not be worked around with more aggressive CoreBluetooth reconnect loops.

## Next physical test

The next user test is **INDOOR ONLY** and must be short. Do not ask for another ride yet.

1. Launch the authenticated Capture build.
2. Authenticate through a supported Tuya mechanism for the user's already-bound device/account.
3. Connect to the same physical peripheral / Tuya device.
4. Subscribe to the FD50 notify characteristic.
5. Keep the scooter stationary and untouched.
6. Observe for at least 45 seconds.
7. Pass only if BOTH are true:
   - at least one real, non-empty application notification payload is received after authentication; and
   - the authenticated connection remains alive beyond the previous 30-second rejection window.
8. Export the read-only authentication/preflight capture.

No charger, wheel movement, riding, mode switching, light switching, braking, or throttle action is required for this preflight.

## Safe implementation boundary

The accepted implementation path is the official Tuya SmartLife App SDK (or another documented Tuya mechanism with equivalent authorization provenance). Current official iOS SDK documentation requires a Tuya Developer Platform SDK app configuration including matching Bundle ID, AppKey, AppSecret/security material, SDK initialization, user login/home/device access, and Bluetooth components.

The fact that the user is already logged into the consumer Tuya app does **not** authorize Nembra to scrape the Tuya app's sandbox, Keychain, private files, process memory, or credentials.

### Allowed application writes

Only protocol messages emitted by the official/documented Tuya authentication/session establishment implementation are allowed during this preflight. They are transport/authentication writes, not scooter DP control.

After authentication completes, Capture remains read-only: subscribe/receive/query only through documented non-mutating APIs. Unknown DP/control writes remain disabled.

### Explicitly forbidden

- guessed raw FD50 application packets
- brute forcing keys, tokens, local keys, UUIDs, or counters
- arbitrary DP writes
- lock/unlock writes
- speed-limit or mode writes
- throttle, brake, regen, cruise, or light commands
- unbind/remove-device operations
- factory reset / pairing reset
- OTA/firmware changes
- extracting credentials from another app's storage or memory

## Credential/privacy QA

Fail closed if the authorized Tuya session cannot be established.

Never write any of the following into Capture JSON, console logs, analytics, crash breadcrumbs, screenshots, Git history, or UI debug text:

- Tuya account password
- access/refresh tokens
- AppSecret
- device/local/session keys
- pairing tokens
- decrypted session material

Export may contain only non-secret evidence such as authentication state transitions, opaque error categories, timestamps, connection duration, service/characteristic UUIDs, notification byte payloads that the authorized session exposes, and scenario markers.

Reconnect must discard ephemeral session state and re-establish authentication through the documented mechanism. Do not reuse stale session material merely to survive the 30-second timeout.

## Fail-closed UI behavior

Until authenticated payload acceptance passes:

- show `Tuya authentication required` rather than starting the 17-step calibration;
- offer only the short indoor authenticated preflight;
- keep full outdoor calibration disabled;
- do not claim battery/speed/power/mode mapping readiness;
- do not interpret GPS samples as scooter telemetry.

If authentication support is not configured in the build, say exactly what is missing (for example SDK application configuration), and stop before connecting for a calibration run.

## Acceptance criteria

### PASS

- authorized Tuya account/device session established using a documented mechanism
- same intended device reached
- FD50 notify subscription succeeds
- non-empty application notification payload received
- authenticated BLE session remains connected for >45 seconds without the old ~30-second illegal-connection drop
- no credential/session secret appears in export or logs
- no control/unbind/reset/OTA action is invoked

### FAIL

Any one of:

- no documented authorization provenance
- guessed packet/key use
- zero notify application payloads
- disconnect at/near the prior ~30-second window
- credentials/session material leak into output
- any scooter-control DP write
- any unbind/reset/OTA side effect

## What happens after PASS

Do a stationary mapping pass before any outdoor repeat:

1. idle baseline
2. current Tuya-app battery/odometer reference recorded as operator reference only
3. ECO / Drive / Sport local-control transitions if available
4. light off/on local-control transitions
5. brake held/pulses
6. optional charger transition, indoors and skippable

Only once authenticated DP payload deltas are repeatable should Nembra label telemetry semantics. Movement/GPS calibration is the final step, not the next step.
