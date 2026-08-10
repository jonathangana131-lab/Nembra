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

This statement identifies the transport family only. It does not authorize any scooter telemetry or command semantic.

## Telemetry truth boundary

Until a documented Tuya-authenticated session produces real notification payloads and those payloads are physically correlated against repeatable scenarios, the following remain unknown/unavailable:

- battery state of charge
- battery voltage/current/power
- charging state
- vehicle speed
- throttle state
- brake state
- ECO / Drive / Sport mapping
- headlight state
- cruise control
- lock state
- speed-limit data points
- trip / odometer data points
- controller temperature or motor telemetry

No UI, parser, simulator fixture, GPS sample, scenario marker, or user-entered reference may be promoted into Bluetooth-derived truth for these fields.

## User-supplied lifetime odometer continuity

The operator supplied three historical odometer segments because the scooter/Tuya-visible counter reset twice:

- pre-reset segment 1: `665.3 mi`
- pre-reset segment 2: `429.5 mi`
- current Tuya-visible counter: `1070.0 mi`
- user-supplied lifetime continuity total: `2164.8 mi`

Classification: **userReferenceHistory**.

This is useful continuity metadata, but it is not BLE evidence, not a device DP reading, not ride-engine distance, and not a reconciled measured odometer. Nembra must preserve that provenance explicitly. A future authenticated scooter odometer DP may be displayed alongside or reconciled with this reference only through an explicit reconciliation rule; it must never silently replace, validate, or relabel the user reference.

## Next physical gate — authenticated read-only preflight

The next physical run is intentionally much smaller than the first outdoor calibration.

Acceptance requirements:

1. Use a documented Tuya authentication/account/key mechanism appropriate to an already-bound device.
2. Do not guess raw application commands.
3. Do not unbind, factory-reset, re-pair, or modify scooter configuration merely to obtain telemetry.
4. Keep credentials/tokens/local keys out of source control and capture exports.
5. Establish the FD50 notification subscription after authentication.
6. Receive at least one real application notification payload.
7. Keep the authenticated BLE session alive beyond the prior approximately-30-second rejection window.
8. Record authentication state transitions and payload bytes without assigning DP semantics yet.

Only after this gate passes should physical semantic mapping begin.

## Mapping order after authentication

Perform stationary correlation first: untouched idle, battery reference, optional charger transition, mode changes, headlight, brake hold/pulses. Accept a DP meaning only after repeatable byte/value correlation.

Repeat movement/GPS testing only after stationary payloads prove that authenticated telemetry is flowing. Outdoor work should then be limited to the smallest set required to identify speed, trip/odometer growth, and any motion-dependent power/current values.

## Safety boundary

The Capture lane remains observation-first. Unknown writes, guessed DP controls, unbinding, reset behavior, motor actuation, speed-limit changes, lock changes, and other state-changing experiments are outside this gate.

This ledger supersedes any prior project text that still says Nembra is waiting for its first real Bluetooth JSON artifact.