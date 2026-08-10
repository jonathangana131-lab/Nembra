# Physical Truth Ledger — Capture C7D09A22

Status: accepted physical evidence boundary for the first real scooter capture.

## Artifact identity

- Capture ID: `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E`
- Selected CoreBluetooth peripheral: `6815A5F5-4D1E-E004-BAE8-6DF924123907`
- Connected peripheral name: `Simple Peripheral`
- Power-on local advertisement name: `demo`
- Tuya Bluetooth LE service family: `FD50`
- Guided scenarios completed: `17 / 17`
- Application characteristic payload count: `0`
- Observed peripheral-initiated disconnect cadence: approximately 30 seconds, repeatedly

## Accepted transport truth

This capture is sufficient to treat the scooter as a Tuya FD50 Bluetooth LE transport device. The observed GATT shape is Tuya-style: one app-to-device write characteristic and one device-to-app notify characteristic under FD50.

This identifies the transport family only. It does not authorize any scooter telemetry or command semantic.

## Telemetry truth boundary

Until a documented Tuya-authenticated session produces real application data and those values are physically correlated against repeatable scenarios, the following remain unknown/unavailable:

- battery state of charge;
- battery voltage/current/power;
- charging state;
- vehicle speed;
- throttle state;
- brake state;
- ECO / Drive / Sport mapping;
- headlight state;
- cruise control;
- lock state;
- speed-limit data points;
- trip / odometer data points;
- controller temperature or motor telemetry.

No UI, parser, simulator fixture, GPS sample, scenario marker, SDK metadata, or user-entered reference may be promoted into Bluetooth-derived truth for these fields.

## User-supplied lifetime odometer continuity

The operator supplied three historical odometer segments because the scooter/Tuya-visible counter reset twice:

- pre-reset segment 1: `665.3 mi`
- pre-reset segment 2: `429.5 mi`
- current Tuya-visible counter: `1070.0 mi`
- user-supplied lifetime continuity total: `2164.8 mi`

Classification: **userReferenceHistory**.

This is useful continuity metadata, but it is not BLE evidence, not a device DP reading, not ride-engine distance, and not a reconciled measured odometer. Nembra must preserve that provenance explicitly. A future authenticated scooter odometer DP may be displayed alongside or reconciled with this reference only through an explicit reconciliation rule; it must never silently replace, validate, or relabel the user reference.

## Next physical gate — SDK-owned authenticated read-only preflight

The next physical run is intentionally much smaller than the first outdoor calibration. Current procedure: `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`.

Acceptance requirements:

1. Correlate the intended physical scooter using accepted deterministic local discovery evidence; name/RSSI/ranking alone are not authority.
2. Stop Nembra's CoreBluetooth scan before authentication begins.
3. Initialize/login the official Tuya SDK with the matching private application identity.
4. Fully enumerate/load the SDK account's homes and verify the exact selected scooter `deviceID` in owned/shared membership; partial enumeration fails closed.
5. Let the official/documented Tuya SDK exclusively own the authenticated BLE connection.
6. Keep credentials, verification codes after use, tokens, local keys, generated security material, and session secrets out of source control and exports.
7. Bind the attempt to one canonical `TuyaAuthenticatedReadOnlySessionLedger` token/generation.
8. Admit only non-empty structured SDK application updates for that same generation using the canonical ledger API; do not manufacture raw bytes from decoded values.
9. Prove the canonical authenticated chronology reaches at least 45 monotonic seconds while Tuya local BLE is observably online and without a disqualifying observation gap.
10. Require `TuyaAuthenticatedReadOnlyPreflight` to return `readyForStationaryMapping` for that generation.
11. Send no scooter DP query or publish/control command and perform no unbind/reset/re-pair/configuration change.
12. Export sanitized diagnostic evidence without assigning DP semantics.

### Payload provenance correction

The current SDK-owned observation path receives application-level/decoded `ThingSmartDeviceDelegate` DP callbacks. Those values are authenticated application evidence only after the full same-generation acceptance gate is satisfied, but they are **not raw FD50 characteristic bytes**.

The current field app may include descriptive string projections of opaque SDK DP IDs/values for diagnostics. Those projections are not byte-exact or lossless payload authority. Canonical chronology records structured-update presence rather than invented serialized payload bytes.

Raw FD50 bytes remain a distinct evidence class and are not currently required to pass this preflight. Current authenticated-preflight export explicitly records `rawFD50BytesCaptured = false`. Raw bytes may be claimed only if a later same-session authority proves their provenance. Opening a second independent CoreBluetooth connection after Tuya owns the session is not acceptable proof.

### Chronology provenance correction

The >45-second requirement is an **observed monotonic authenticated-session window**, not wall-clock elapsed time. The app must sample local-BLE currentness frequently enough to preserve the accepted continuity contract. A long foreground-observation/event-loop gap fails closed before liveness advances; the missing interval cannot be backfilled as proof.

Each attempt uses a fresh generation-bound opaque ledger token. Stale callbacks from a retired generation cannot mutate a newer generation or revive a failed attempt.

Only after this gate passes should physical semantic mapping begin.

## Mapping order after authentication

Perform stationary correlation first: untouched idle, battery reference, mode changes, headlight, brake hold/pulses, and optional charger transition. Accept a DP meaning only after repeatable value correlation.

Repeat movement/GPS testing only after stationary application values prove authenticated telemetry is flowing. Outdoor work should then be limited to the smallest set required to identify speed, trip/odometer growth, and any motion-dependent power/current values.

## Safety boundary

The Capture lane remains observation-first. Unknown writes, guessed Tuya frames, secondary post-auth CoreBluetooth connections, score/name/RSSI-only target authority, invented raw payload bytes, DP query/publish during this gate, unbinding, reset behavior, motor actuation, speed-limit changes, lock changes, and other state-changing experiments are outside authority.

This ledger supersedes prior project text that says Nembra is waiting for its first real Bluetooth JSON artifact, and its next-gate section supersedes older wording that requires raw FD50 bytes from the SDK-owned authenticated preflight.
