# Physical capture C7D09A22 — truth ledger

Status: accepted physical observation record. This document records evidence; it does not authorize scooter control writes.

## Observed physical transport

- Capture ID: `C7D09A22`
- Selected CoreBluetooth peripheral: `6815A5F5-4D1E-E004-BAE8-6DF924123907`
- Observed local name: `demo`
- Transport family: Tuya BLE / FD50
- Guided scenarios completed: 17 / 17
- Application characteristic payloads observed: 0
- Connection behavior: repeated peripheral-initiated disconnects at approximately 30 seconds while the client was not Tuya-authenticated.

These observations establish transport-family evidence only. They do **not** establish the meanings, units, scaling, cadence, or authority of speed, battery, odometer, mode, lights, brake, throttle, current, voltage, power, temperature, regen, cruise, or any other Tuya DP.

## Odometer continuity reference — user supplied, not BLE derived

The user reports that the scooter's displayed Tuya odometer reset twice and preserved the prior readings manually:

- pre-reset segment 1: 665.3 mi
- pre-reset segment 2: 429.5 mi
- current Tuya display: 1070.0 mi
- continuity sum: **2164.8 mi**

Nembra MUST represent `2164.8 mi` only as explicit user/reference history until authenticated physical device payloads independently establish an odometer DP and its semantics. It MUST NOT label, serialize, migrate, or present this value as Bluetooth-measured, device-reported lifetime mileage, or a protocol-derived correction.

If a future authenticated device odometer differs, retain both facts with provenance rather than silently replacing one with the other.

## P0 next evidence gate

The next physical experiment is a minimal Tuya-authenticated **read-only** preflight on `capture/one-time-ble-dump-gpt56`.

Required acceptance:

1. Authenticate through documented Tuya mechanisms using credentials/keys belonging to the user's own Tuya-bound device/account.
2. Subscribe to the already observed notification path without issuing guessed application commands.
3. Receive at least one real application characteristic payload.
4. Maintain the authenticated connection beyond the prior ~30-second rejection window.
5. Keep secrets out of logs, JSON exports, source control, screenshots, and analytics.
6. Fail closed if required authentication material is unavailable or invalid.

Forbidden in this gate: arbitrary/guessed characteristic writes, guessed DP controls, unbind/remove-device operations, factory reset, pairing reset, motor commands, speed-limit changes, or any attempt to bypass Tuya account/device authorization.

Only after this gate produces authenticated payload evidence may stationary scenario correlation begin. Outdoor riding is not required merely to prove authentication.
