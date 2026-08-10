# Capture C7D09A22 — First physical scooter BLE findings

Source artifact: `Nembra-Scooter-Learning-C7D09A22.json` (preserve the user's original artifact unchanged outside this repository note).

## Verified physical facts

- Capture ID: `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E`
- Selected CoreBluetooth peripheral: `6815A5F5-4D1E-E004-BAE8-6DF924123907`
- Connected name: `Simple Peripheral`
- Power-on advertisement local name: `demo`
- Power-on advertisement was connectable and newly appeared after the scooter was powered on.
- Advertisement exposed service UUID `FD50`.
- Manufacturer data starts with little-endian company identifier `D0 07` (Bluetooth SIG company identifier 0x07D0, assigned to Hangzhou Tuya Information Technology Co., Ltd.).
- GATT service: `FD50`.
- Characteristic `00000001-0000-1001-8001-00805F9B07D0`: write / write-without-response.
- Characteristic `00000002-0000-1001-8001-00805F9B07D0`: notify.
- CCCD `2902` exists and CoreBluetooth successfully enabled notifications.
- No application characteristic value callbacks were received: `characteristicValueEventCount = 0`.
- 17/17 guided scenarios were completed and 474 iPhone location-reference samples were captured.
- The connection was dropped by the peripheral 15 times with `CBErrorDomain` code 7.
- Measured connected intervals before each drop were 29.913–29.974 seconds; mean 29.930 seconds with ~0.0205 s population standard deviation.
- Capture auto-reconnect recovered each observed transient drop quickly enough to preserve scenario progress.

## Protocol identification

These identifiers exactly match Tuya's current Bluetooth LE transport:

- Registered service UUID: `FD50`
- App-to-device write characteristic: `00000001-0000-1001-8001-00805F9B07D0`
- Device-to-app notify characteristic: `00000002-0000-1001-8001-00805F9B07D0`
- Manufacturer company identifier: `0x07D0`

Tuya documents that an unpaired/unauthenticated connection that does not complete its application-layer pairing exchange is removed after about 30 seconds as an illegal connection. The physical capture's extremely repeatable ~29.93 s disconnect cadence, combined with zero notify payloads despite a successful subscription, is therefore strong evidence that the missing layer is Tuya pairing/authentication rather than RF instability or a Nembra reconnect defect.

## What is NOT verified yet

No scooter application payload was received, so no data-point mapping is accepted yet for:

- speed
- battery / charging
- power / current / voltage
- ECO / Drive / Sport
- brake / throttle
- light
- lock / cruise / speed limit
- odometer / trip data

Do not invent these mappings from GPS or scenario timing.

## Next experiment — targeted, not another full ride

1. Do **not** repeat the outdoor calibration yet.
2. Add a Tuya-aware secure-link/authentication preflight using a documented Tuya mechanism; do not guess arbitrary raw writes.
3. First acceptance gate: notification characteristic produces real application payloads and the connection remains alive beyond the prior 30-second rejection window.
4. Once payload exists, perform a short stationary mapping pass first (idle, battery reference, modes, light, brake, optional charger transition).
5. Only after stationary DPs are visible should movement/GPS segments be repeated for speed/power correlation.
6. Unknown/control DPs remain disabled until repeatable physical evidence verifies their semantics.

This artifact closes transport-family and timeout-cause discovery. It does **not** close telemetry semantics.