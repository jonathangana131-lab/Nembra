# Capture C7D09A22 — Tuya-authenticated read-only preflight

Status: supporting implementation/truth contract for the next physical run. The canonical current field procedure is `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`; if this historical-support document ever conflicts with that procedure, the canonical current procedure wins. This supersedes repeating the 17-step outdoor calibration before authentication is solved.

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

The historical CoreBluetooth peripheral UUID, advertising name, FD50 presence, Tuya manufacturer/product hints, and RSSI are descriptive facts from the old capture only. None of them authorizes the current attempt or may break a target-correlation tie.

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

SDK login alone is **not** device authority. Before Bluetooth target correlation can start, Capture must fully enumerate the SDK account's homes and find the exact expected scooter Tuya device ID in owned/shared membership. Partial home loading, a different device, name similarity, RSSI, category, or display-name hints fail closed.

After exact membership is proven, the app must complete one fresh package-owned `OFF1 → ON1 → OFF2 → ON2` correlation series using full CoreBluetooth peripheral identity, mechanically earning scan readiness and the accepted receipt-bounded duration in each window. Exactly one repeatable full UUID plus explicit operator confirmation is required for the current attempt. No historical UUID, FD50, Tuya-company/manufacturer hint, name, RSSI, or score may replace or override that result.

Only after that fresh correlation + confirmation and a fresh same-account exact-membership recheck may Capture ask Tuya's SDK to connect the already-activated BLE device by its documented UUID + product ID path. No device pairing/removal/activation API is permitted in this preflight build.

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
   - one package-owned fresh-manager `OFF1 → ON1 → OFF2 → ON2` series is completed in the accepted order;
   - every window proves scan readiness and the accepted receipt-bounded minimum duration before sealing;
   - the package reports exactly one repeatable full CoreBluetooth UUID;
   - the operator explicitly confirms that freshly correlated target for this attempt;
   - the historical C7D09A22 UUID, FD50, Tuya company/manufacturer data, name, RSSI, power-on delta and score are descriptive only and cannot authorize or break a tie;
   - none/ambiguous/provenance-invalid results are terminal STOP outcomes that require a fresh OFF1 restart.

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
   - exact SDK scooter membership remains proven for the same current account; AND
   - the current attempt still carries the explicitly confirmed fresh four-window target correlation; AND
   - the current generation carries accepted SmartLife SDK authentication provenance; AND
   - Tuya local BLE is still online; AND
   - at least one same-generation post-auth non-empty `dpsUpdate` exists; AND
   - canonical authenticated observation reaches at least `45 s`; AND
   - no unacceptable observation gap occurred; AND
   - the accepted prefix is sealed before UI success; AND
   - no unbind/reset/pair/activation/control action occurred.

9. `failed`
   - on membership failure, target-correlation invalidation/ambiguity, authentication rejection, local-BLE loss, stale chronology, observation gap, or no application update within the accepted diagnostic window, export the sanitized diagnostic artifact when available and stop;
   - asynchronous package correlation invalidation must land in an explicit fail-closed fresh-OFF1 restart state rather than trapping the operator in a disabled window;
   - do not automatically retry forever and do not move to outdoor scenarios.

## Application-data truth boundary

The current SDK adapter receives structured `dpsUpdate` dictionaries. It does **not** expose byte-exact raw FD50 notification frames.

Therefore this preflight may prove:

- an officially authenticated SDK session;
- exact scooter account membership;
- a fresh current-attempt correlated Bluetooth target;
- local-BLE continuity;
- receipt of genuine structured scooter application updates;
- update chronology and count;
- opaque DP key/value projections useful for later correlation.

It may **not** claim that serializing those dictionaries produces raw FD50 bytes. Raw FD50 transport capture remains a separate future evidence problem if needed.

## Diagnostic export requirements

The sanitized JSON should include:

- purpose/schema/build identity;
- exact Tuya device ID / UUID / product ID needed to identify the tested SDK target;
- selected current-attempt CoreBluetooth peripheral ID plus the accepted four-window correlation provenance;
- SDK compiled/private-config/account-login/exact-membership states;
- authentication method and current connection generation;
- secure-session age / local-BLE state;
- application update count and sanitized opaque DP string projections;
- canonical preflight verdict;
- `rawFD50BytesCaptured: false`;
- `secretsRedacted: true`;
- `dpCommandsSent: false`;
- explicit failure/event chronology.

For an accepted attempt, application evidence/event chronology must be serialized from the immutable accepted prefix, not from later mutable post-seal diagnostics.

It must contain no account password, verification code, cloud token, AppSecret, AppKey, `local_key`, session/auth key, private Cryption material, or QR authorization token.

## First physical acceptance gate

Do not repeat the full outside run until ALL are true in one current attempt/generation:

1. authoritative exact field-build provenance is present on the intended iPhone 12 / iOS 27 field build;
2. official SDK account is authorized;
3. exact scooter device membership is freshly verified for that same current SDK account;
4. one package-owned fresh `OFF1 → ON1 → OFF2 → ON2` series produces exactly one repeatable full CoreBluetooth UUID and the operator explicitly confirms it for this attempt;
5. supported SmartLife SDK authentication succeeds and Tuya local BLE is online;
6. at least one genuine same-generation post-auth `dpsUpdate` is observed;
7. canonical authenticated observation reaches at least `45 s` without an unacceptable gap;
8. the accepted application/event prefix is sealed before success/export authority;
9. no command/pair/reset/unbind/activation path was used.

If correlation is none/ambiguous, package scan readiness or chronology invalidates, source/account authority changes, or any other terminal occurs, stop and follow the exact blocker. Do not substitute historical UUID/name/RSSI/FD50/Tuya hints and do not continue to authentication on a guessed target.

After that passes, the **next** experiment remains stationary. Choose the smallest DP-correlation sequence justified by the captured structured application data before considering any later short outdoor motion/power experiment.
