# ES80 Physical Truth — Capture C7D09A22

Status: accepted physical transport evidence. Telemetry semantics remain unverified.

This field artifact supersedes the stale physical NO-GO ceremony recorded in #833 for the transport rung it actually proves. It does **not** supersede the remaining telemetry/authentication NO-GO: no application payload has yet been observed and no ES80 DP semantics are physically accepted.

## Source artifact

- Capture ID: `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E`
- Selected CoreBluetooth peripheral in this capture: `6815A5F5-4D1E-E004-BAE8-6DF924123907`
- Power-on local name: `demo`
- Guided scenarios completed: `17/17`
- Application characteristic payload count: `0`
- Peripheral-initiated disconnects: `15`
- Mean connected interval before rejection: approximately `29.930 s`

The CoreBluetooth peripheral UUID above is historical capture-local evidence only. It is not accepted as a durable physical scooter identity.

## Verified transport facts

The physical scooter exposed the modern Tuya FD50 GATT family:

- service: `FD50`
- app-to-device characteristic: `00000001-0000-1001-8001-00805F9B07D0` (`write`, `writeWithoutResponse`)
- device-to-app characteristic: `00000002-0000-1001-8001-00805F9B07D0` (`notify`)
- CCCD: `2902`
- power-on advertisement manufacturer data begins with Tuya company identifier `0x07D0`

These are now physical ES80 transport facts, not merely generic Tuya candidates.

## What this capture does NOT authorize

Because the capture received zero application characteristic payloads, it does not establish any ES80 DP ID, type, scale, signedness, cadence, or command acknowledgement semantics. The following remain unknown until authenticated physical payload evidence exists:

- speed
- battery percentage or charging state
- voltage
- current
- wattage / power
- ECO / Drive / Sport mode
- brake / throttle
- light
- lock / cruise / speed limit
- trip mileage
- odometer

GPS and scenario timing must never be transformed into Bluetooth semantics. Unknown telemetry remains `unavailable`; it must not be synthesized, guessed, backfilled from GPS, or promoted from simulator/generic Tuya assumptions.

## Odometer continuity boundary

The scooter owner supplied a separate historical continuity record after two displayed-odometer resets:

- `665.3 mi`
- `429.5 mi`
- current Tuya display at reference time: `1070.0 mi`
- user-reference lifetime continuity total: `2164.8 mi`

This is **user-recorded history**, not Bluetooth evidence. Nembra must keep it separate from `VehicleState.odometerKilometers` and from any future device-reported odometer value. A later authenticated device value may be physically reconciled against this history, but it must not silently overwrite, validate, or relabel the user record.

## Connection interpretation

The physical connection ended repeatedly at a highly stable approximately-30-second cadence while notification subscription succeeded but no application payload arrived. This makes a legitimate Tuya authenticated application session the narrow next experiment; repeating the full outdoor calibration before that would add movement evidence without unlocking application telemetry.

Authentication success is not yet physical fact and must be demonstrated in a subsequent capture.

## P0 next physical gate — authenticated, read-only, credential-private

Capture may implement only the documented Tuya authentication/session establishment needed to receive device notifications. The experiment boundary is intentionally narrow:

1. Use a legitimate, documented Tuya authenticated connection flow for the already-bound scooter.
2. Treat every account/device credential, token, secret, local key, session key, or equivalent credential material as private. Do not commit it, print it into normal logs, attach it to fixtures/artifacts, or persist it outside the minimum private runtime storage required for the session.
3. Keep the first authenticated experiment read-only at the product-semantic level. Writes are permitted only where the documented Tuya authentication/session protocol itself requires them to establish the authenticated notification channel.
4. Do **not** send arbitrary DP/control writes. Do **not** unbind, re-pair by reset, factory-reset, change ownership, change settings, toggle controls, or attempt undocumented mutation commands.
5. Subscribe to the real FD50 device-to-app notification characteristic and preserve received application bytes verbatim as evidence before interpreting them.

The authenticated gate is accepted only when **all** shipping preflight conditions are demonstrated in the same real physical authenticated generation:

- at least **two** real, non-empty application updates are admitted from the selected scooter, so one bootstrap/state replay cannot mint readiness;
- the latest admitted application update occurs at least **30 seconds after authentication**, proving the authenticated application path itself survived beyond the historical rejection region; and
- accepted authenticated observation continuity reaches at least **45 seconds** after authentication.

This is the minimum acceptance boundary. One payload is insufficient. A latest payload before the 30-second post-authentication mark is insufficient. A 31–44 second authenticated connection is insufficient even if it produced application traffic. A connection that lasts longer without the required repeated payload evidence, or payload-shaped simulator/test data without a surviving physical authenticated generation, does not close the gate. An authenticated generation that remains incomplete at the package-owned 60-second horizon must retire fail-closed rather than being promoted by a late callback.

## After gate closure — stationary DP mapping first

Once authenticated notify evidence closes the gate, move immediately into physical DP mapping using stationary scenarios before any repeat outdoor ride. Preserve raw frames and timestamps, change one observable condition at a time, and distinguish observed correlation from accepted semantics.

Recommended stationary sequence:

1. powered-on idle baseline;
2. battery/charger reference while stationary, if safely available;
3. mode changes only through known normal scooter/app controls;
4. light state;
5. brake lever state while stationary;
6. other non-motion observations only after the earlier correlations are repeatable.

No moving/GPS calibration should be repeated until stationary mapping has produced real device payload correlations worth testing under motion.

## Product truth rule

`PhysicalCaptureTransportEvidence.c7d09a22` is the code-level transport ledger. `OdometerContinuityReference.physicalCaptureC7D09A22Reference(...)` is the separate user-history ledger. Neither type may mint physical telemetry without new authenticated payload evidence.

For the real Nembra product, accepted navigation/product work should converge on the canonical spine:

`Dashboard/Cockpit -> Battery/Range -> Rides/Records -> Navigation -> Home -> Vehicle/Controls`

Reconciliation must preserve evidence authority: unavailable or physically unknown telemetry stays unavailable, and the `2164.8 mi` continuity figure remains reference-only until reconciled against authenticated device evidence.
