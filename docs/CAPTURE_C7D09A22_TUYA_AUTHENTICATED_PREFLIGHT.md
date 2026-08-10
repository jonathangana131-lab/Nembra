# Capture C7D09A22 — Tuya-authenticated read-only preflight

Status: implementation contract for the next physical run. This supersedes repeating the 17-step outdoor calibration before authentication is solved.

## Physical evidence already established

- Capture: `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E`
- Selected CoreBluetooth peripheral: `6815A5F5-4D1E-E004-BAE8-6DF924123907`
- Advertising local name: `demo`
- Tuya service: `FD50`
- App -> device characteristic: `00000001-0000-1001-8001-00805F9B07D0` (`write` / `writeWithoutResponse`)
- Device -> app characteristic: `00000002-0000-1001-8001-00805F9B07D0` (`notify`)
- Captured raw application characteristic payloads in that old passive run: `0`
- Completed physical scenarios: `17/17`
- Peripheral-initiated disconnects: `15`
- Measured connected lifetime before each rejection: approximately `29.93 s`

Tuya's published BLE documentation defines `FD50` and these characteristic UUIDs, and describes bound-but-unauthenticated connection state. Therefore the next run is an authentication experiment, not another telemetry-mapping ride.

## Safety boundary

The preflight MUST NOT:

- guess raw Tuya frames;
- brute-force keys, DPs, opcodes, sequence values, checksums, or encryption;
- unbind, remove, reset, factory-reset, activate, re-pair, or re-authorize the scooter;
- write any user-facing control DP (speed limit, lock, light, mode, cruise, motor, brake, firmware, calibration);
- log Tuya passwords, account tokens, AppSecret, local/session keys, auth keys, device secrets, QR authorization tokens, or full decrypted secure frames;
- claim speed/battery/power/mode/brake/light/odometer semantics before repeatable authenticated application evidence exists.

The cloud `local_key` returned by the already-authorized metadata route may be retained privately for evidence continuity, but it is **not** accepted by itself as proof of FD50 BLE authentication material. The physical gate must carry an accepted official authentication-method provenance from the session provider.

## Accepted authentication route for this field build

The current implementation uses Tuya's SmartLife App SDK for iOS so account/device ownership and BLE secure-channel establishment remain inside Tuya's supported SDK. The private field workspace must be configured with the app-specific Tuya security package plus the AppKey/AppSecret matching bundle `com.jonathangana131.nembra.capturelearn`.

The user's SDK account is authorized by verification code. Nembra does not collect or persist the Tuya account password.

SDK login alone is **not** device authority. Before Bluetooth authentication can start, Capture must fully enumerate the SDK account's homes and find the exact expected scooter Tuya device ID in owned/shared membership. Partial home loading, a different device, name similarity, RSSI, category, or display-name hints fail closed.

After exact membership is proven, Capture may ask Tuya's SDK to connect the already-activated BLE device by its documented UUID + product ID path. No device pairing/removal/activation API is permitted in this preflight build.

## Read-only preflight state machine

1. `notConfigured`
   - app-specific Tuya security SDK and/or private app identity are absent;
   - UI says provisioning is required;
   - no physical authentication test is authorized.

2. `sdkAccountAuthorized`
   - the official Tuya SDK is initialized with the matching private app identity;
   - the user's SDK account session is logged in through the supported verification-code flow.

3. `exactDeviceMembershipVerified`
   - all relevant homes load successfully;
   - the exact metadata-selected scooter device ID appears in owned/shared device membership;
   - login, names, RSSI and broad Tuya hints alone cannot satisfy this state.

4. `targetCorrelated`
   - CoreBluetooth discovery is passive and stops before Tuya's SDK takes BLE ownership;
   - the physical candidate requires the previously observed CoreBluetooth identity OR combined FD50 + Tuya-company evidence;
   - score, name, RSSI and power-on delta can rank/display candidates but cannot independently authorize one.

5. `secureConnecting`
   - a fresh `TuyaAuthenticatedReadOnlySessionLedger` connection generation is minted;
   - authentication-start chronology is recorded;
   - Tuya's official SDK becomes the sole BLE connection owner;
   - no Nembra-authored raw application command frame is sent.

6. `authenticatedObservation`
   - SDK connection success is accepted only when Tuya reports the expected UUID locally BLE-connected;
   - the ledger records `.smartLifeAppSDK` provenance;
   - a 45-second stationary canonical observation begins;
   - observation continuity fails closed if the accepted polling/liveness gap is exceeded.

7. `applicationEvidenceObserved`
   - at least one non-empty `ThingSmartDeviceDelegate.dpsUpdate` is received **after authentication in the same ledger generation**;
   - the ledger records only the fact/chronology of non-empty structured application evidence;
   - stale, cross-ledger, pre-authentication or retired-generation callbacks cannot promote the gate.

8. `accepted`
   - exact SDK scooter membership remains proven; AND
   - the current generation carries accepted SmartLife SDK authentication provenance; AND
   - Tuya local BLE is still online; AND
   - at least one same-generation post-auth non-empty `dpsUpdate` exists; AND
   - canonical authenticated observation reaches at least `45 s`; AND
   - no unacceptable observation gap occurred; AND
   - no unbind/reset/pair/activation/control action occurred.

9. `failed`
   - on membership failure, authentication rejection, local-BLE loss, stale chronology, observation gap, or no application update within the accepted diagnostic window, export the sanitized diagnostic artifact and stop;
   - do not automatically retry forever and do not move to outdoor scenarios.

## Application-data truth boundary

The current SDK adapter receives structured `dpsUpdate` dictionaries. It does **not** expose byte-exact raw FD50 notification frames.

Therefore this preflight may prove:

- an officially authenticated SDK session;
- exact scooter account membership;
- local-BLE continuity;
- receipt of genuine structured scooter application updates;
- update chronology and count;
- opaque DP key/value projections useful for later correlation.

It may **not** claim that serializing those dictionaries produces raw FD50 bytes. Raw FD50 transport capture remains a separate future evidence problem if needed.

## Diagnostic export requirements

The sanitized JSON should include:

- purpose/schema/build identity;
- exact Tuya device ID / UUID / product ID needed to identify the tested target;
- selected CoreBluetooth peripheral ID;
- SDK compiled/private-config/account-login/exact-membership states;
- authentication method and current connection generation;
- secure-session age / local-BLE state;
- application update count and sanitized opaque DP string projections;
- canonical preflight verdict;
- `rawFD50BytesCaptured: false`;
- `secretsRedacted: true`;
- `dpCommandsSent: false`;
- explicit failure/event chronology.

It must contain no account password, verification code, cloud token, AppSecret, AppKey, `local_key`, session/auth key, private Cryption material, or QR authorization token.

## First physical acceptance gate

Do not repeat the full outside run until ALL are true in one current generation:

1. official SDK account is authorized;
2. exact scooter device membership is verified;
3. supported SmartLife SDK authentication succeeds and Tuya local BLE is online;
4. at least one genuine same-generation post-auth `dpsUpdate` is observed;
5. canonical authenticated observation reaches at least `45 s` without an unacceptable gap;
6. no command/pair/reset/unbind/activation path was used.

After that passes, the **next** experiment remains stationary. Choose the smallest DP-correlation sequence justified by the captured structured application data before considering any later short outdoor motion/power experiment.
