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

No UI, parser, simulator fixture, GPS sample, scenario marker, or user-entered reference may be promoted into Bluetooth-derived truth for these fields.

## User-supplied lifetime odometer continuity

The operator supplied three historical odometer segments because the scooter/Tuya-visible counter reset twice:

- pre-reset segment 1: `665.3 mi`
- pre-reset segment 2: `429.5 mi`
- current Tuya-visible counter: `1070.0 mi`
- user-supplied lifetime continuity total: `2164.8 mi`

Classification: **userReferenceHistory**.

This is useful continuity metadata, but it is not BLE evidence, not a device DP reading, not ride-engine distance, and not a reconciled measured odometer. Nembra must preserve that provenance explicitly. A future authenticated scooter odometer DP may be displayed alongside or reconciled with this reference only through an explicit reconciliation rule; it must never silently replace, validate, or relabel the user reference.

## Next physical gate — SDK-owned authenticated read-only preflight

The next physical run is intentionally much smaller than the first outdoor calibration. Current procedure: `docs/CAPTURE_NEXT_TUYA_SECURE_LINK_TEST.md`.

Acceptance requirements:

1. Correlate the intended physical scooter using accepted local discovery evidence.
2. Stop Nembra's CoreBluetooth scan before authentication begins.
3. Let the official/documented Tuya SDK exclusively own the authenticated BLE connection.
4. Use the user's authorized already-bound Tuya device/account context; do not guess authentication material.
5. Keep credentials, tokens, local keys, generated security material, and session secrets out of source control and exports.
6. Prove Tuya's local-BLE status remains online continuously for more than 45 seconds after the SDK session succeeds.
7. Receive at least one non-empty genuine `ThingSmartDeviceDelegate` application/DP update from the SDK-owned device session.
8. Record authentication state, monotonic continuity evidence, opaque application-update evidence, and failure state without assigning DP semantics.
9. Send no scooter DP query or publish/control command and perform no unbind/reset/re-pair/configuration change.

### Payload provenance correction

The current SDK-owned observation path receives application-level/decoded DP callbacks. Those values are authenticated application evidence when the acceptance gate is satisfied, but they are **not raw FD50 characteristic bytes**.

Raw FD50 bytes remain a distinct evidence class and are not currently required to pass this preflight. They may be claimed only if a later same-session authority proves their provenance. Opening a second independent CoreBluetooth connection after Tuya owns the session is not acceptable proof.

Only after this gate passes should physical semantic mapping begin.

## Mapping order after authentication

Perform stationary correlation first: untouched idle, battery reference, mode changes, headlight, brake hold/pulses, and optional charger transition. Accept a DP meaning only after repeatable value correlation.

Repeat movement/GPS testing only after stationary application values prove authenticated telemetry is flowing. Outdoor work should then be limited to the smallest set required to identify speed, trip/odometer growth, and any motion-dependent power/current values.

## Safety boundary

The Capture lane remains observation-first. Unknown writes, guessed Tuya frames, secondary post-auth CoreBluetooth connections, DP query/publish during this gate, unbinding, reset behavior, motor actuation, speed-limit changes, lock changes, and other state-changing experiments are outside authority.

This ledger supersedes prior project text that says Nembra is waiting for its first real Bluetooth JSON artifact, and its next-gate section supersedes older wording that required raw FD50 bytes from the SDK-owned preflight.
