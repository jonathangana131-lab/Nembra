# ES80 Physical Truth — Capture C7D09A22

Status: accepted physical transport evidence. Telemetry semantics remain unverified.

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

GPS and scenario timing must never be transformed into Bluetooth semantics.

## Odometer continuity boundary

The scooter owner supplied a separate historical continuity record after two displayed-odometer resets:

- `665.3 mi`
- `429.5 mi`
- current Tuya display at reference time: `1070.0 mi`
- user-reference lifetime continuity total: `2164.8 mi`

This is **user-recorded history**, not Bluetooth evidence. Nembra must keep it separate from `VehicleState.odometerKilometers` and from any future device-reported odometer value. A later authenticated device value may be compared with this history, but it must not silently overwrite, validate, or relabel the user record.

## Connection interpretation

The physical connection ended repeatedly at a highly stable approximately-30-second cadence while notification subscription succeeded but no application payload arrived. This strongly indicates that the next experiment should focus on establishing a legitimate authenticated Tuya application session rather than repeating the entire outdoor calibration.

Authentication success is not yet physical fact and must be demonstrated in a subsequent capture.

## P0 next physical gate

The next test is deliberately smaller than another outdoor calibration:

1. Establish a legitimate authenticated Tuya session without unbinding or resetting the scooter.
2. Keep the capture observational; do not perform unknown scooter-control actions.
3. Require at least one real, non-empty application notification payload.
4. Require the connection to remain alive beyond the previous rejection window; target at least 45 seconds.
5. Only after that gate passes, map stationary telemetry first: idle, battery reference, modes, light, brake, and optional charger transition.
6. Repeat moving/GPS scenarios only after real device payloads exist to correlate.

## Product truth rule

`PhysicalCaptureTransportEvidence.c7d09a22` is the code-level transport ledger. `OdometerContinuityReference.physicalCaptureC7D09A22Reference(...)` is the separate user-history ledger. Neither type may mint physical telemetry without new authenticated payload evidence.
