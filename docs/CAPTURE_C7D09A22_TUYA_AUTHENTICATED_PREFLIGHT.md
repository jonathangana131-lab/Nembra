# Capture C7D09A22 — Tuya-authenticated read-only preflight

Status: implementation contract for the next physical run. This supersedes repeating the 17-step outdoor calibration before authentication is solved.

## Physical evidence already established

- Capture: `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E`
- Selected CoreBluetooth peripheral: `6815A5F5-4D1E-E004-BAE8-6DF924123907`
- Advertising local name: `demo`
- Tuya service: `FD50`
- App -> device characteristic: `00000001-0000-1001-8001-00805F9B07D0` (`write` / `writeWithoutResponse`)
- Device -> app characteristic: `00000002-0000-1001-8001-00805F9B07D0` (`notify`)
- Captured application characteristic payloads: `0`
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
- claim speed/battery/power/mode/brake/light/odometer semantics before repeatable authenticated payload evidence exists.

A `local_key` returned by the account/device metadata flow may be retained privately as provisioning evidence, but its presence MUST NOT by itself be treated as proof that the BLE secure session is authenticated. The physical gate is earned only by current-connection authentication chronology plus a genuine post-auth application notification and the full stability window below.

## Allowed authentication routes

Only an official/documented Tuya route may provide authentication material.

### Preferred route A — SmartLife App SDK for iOS

Use Tuya's SmartLife App SDK so account/device ownership and BLE secure-channel establishment remain inside Tuya's supported SDK. The Nembra build must be configured with a Tuya Developer Platform AppKey/AppSecret that matches the app bundle. The user then logs into their own Tuya account through the SDK. Nembra must never persist the user's account password itself.

After login, Nembra may locate the already-bound scooter in the user's home/device list and ask Tuya's SDK to establish the BLE connection. No device pairing/removal APIs are permitted in this preflight build.

### Alternate route B — official Tuya device-sharing authorization

If App SDK setup is not used, an official Tuya device-sharing / QR authorization flow may be used to grant Nembra read access to the user's already-linked Tuya account/device. This route is acceptable only if it produces documented read access without unbinding/re-pairing the scooter. Keep cloud authorization material out of logs and local JSON exports.

Device-sharing metadata or a retained `local_key` alone does not satisfy the BLE authentication gate. A documented secure-session implementation is still required.

## Read-only preflight state machine

1. `notConfigured`
   - Tuya SDK/app credentials or official device-sharing authorization are absent.
   - UI says authentication setup is required.
   - Do not open the raw FD50 command characteristic.

2. `accountAuthorized`
   - The user's own Tuya account/session is authorized through an official flow.
   - Fetch homes/devices read-only.
   - Identify the existing scooter without changing bindings.

3. `deviceMatched`
   - Match the already-bound Tuya device to physical BLE evidence.
   - Require proximity plus `FD50`, expected advertisement family, and the prior physical peripheral/advertising fingerprint when available.
   - If ambiguous, fail closed rather than connecting to a random nearby Tuya device.

4. `secureConnecting`
   - Ask the official Tuya layer to establish/authenticate BLE.
   - Subscribe to device notifications through the supported stack.
   - No Nembra-authored raw application command frames.

5. `authenticatedObservation`
   - Start a stationary observation only after the current connection generation reaches authenticated state.
   - Record monotonic timestamps for connection start, authentication, each admitted application notification, and the latest observation.
   - Record only metadata needed to prove the channel is alive plus redacted/raw application payload bytes that are safe for protocol analysis.
   - Do not send control commands.

6. `accepted`
   - At least one genuine application notification payload is observed **after authentication in the current connection generation**; AND
   - the authenticated connection remains alive for at least `45 s` measured monotonically from the accepted authentication timestamp; AND
   - connection start <= authentication <= admitted application payload <= latest observation; AND
   - no unbind/reset/pair/activation/control action occurred.

7. `failed`
   - If notifications remain empty, chronology is invalid/stale, or the peripheral repeats the ~30 s rejection, export a small diagnostic artifact and stop. Do not automatically retry forever and do not move to outdoor scenarios.

## Export requirements

The next JSON should add:

- `transportFamily: "tuya-fd50"`
- `authMethod: "tuya-smartlife-sdk" | "tuya-device-sharing"`
- `authenticationResult: "accepted" | "rejected" | "not-configured"`
- current `connectionGeneration`
- monotonic connection-start and authentication timestamps
- `secureConnectionDurationSeconds`
- `applicationNotificationCount`
- notification monotonic timestamp / characteristic UUID / payload hex or base64
- explicit redaction marker proving auth credentials/session keys were excluded
- no account password, cloud token, AppSecret, local/session/auth key, or QR authorization token

A payload count from an older connection generation is not admissible evidence for a newer authenticated connection.

## First physical acceptance gate

Do not repeat the full outside run until BOTH are true:

1. `applicationNotificationCount > 0`, with at least one admitted payload timestamped after authentication in the current connection generation.
2. The authenticated BLE session stays alive for `>= 45 s` after the accepted authentication timestamp.

Once that passes, the next experiment is stationary only: idle -> mode changes -> light -> brake -> optional charger plug/unplug. Only after those DPs are repeatable should speed/power correlation use another short outdoor ride.
