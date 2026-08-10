# Capture — Tuya authenticated read-only preflight QA

Physical evidence source: capture `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E`.

## Verified starting state

- Physical selected peripheral: `6815A5F5-4D1E-E004-BAE8-6DF924123907`.
- Power-on local name: `demo`; connected CoreBluetooth name: `Simple Peripheral`.
- Tuya service: `FD50`.
- App-to-device characteristic: `00000001-0000-1001-8001-00805F9B07D0` (`write`, `writeWithoutResponse`).
- Device-to-app characteristic: `00000002-0000-1001-8001-00805F9B07D0` (`notify`).
- Notification subscription succeeds, but the completed field artifact contains `characteristicValueEventCount = 0`.
- 15 peripheral-initiated `CBErrorDomain` code 7 disconnects occurred at an approximately 29.93-second cadence.
- All 17 guided scenarios completed, but no telemetry/control DP semantics are accepted because no authenticated application payload was observed.

Tuya documentation identifies `FD50` as its proprietary BLE pairing/data service and documents a roughly 30-second illegal/unpaired connection rejection window. The physical cadence matches that behavior closely enough that the next experiment must be authentication-first rather than another outdoor calibration.

## P0 acceptance gate

Do not run another full calibration until all of the following are true in one physical connection:

1. The intended peripheral is selected by the existing OFF -> ON discovery proof; no UUID-only trust across a fresh install/session.
2. Nembra completes a **documented Tuya application-layer authentication/session establishment** for the user's already-bound device. Do not invent packet formats, keys, challenge responses, or DP writes.
3. Credential/key material is never logged, exported into the capture JSON, included in crash text, copied to the pasteboard, or committed to source control.
4. The notify characteristic produces at least one non-empty application payload after authentication.
5. The BLE connection remains continuously alive for **more than 45 seconds** after authentication (comfortably beyond the observed ~29.93-second rejection window).
6. A reconnect performs a fresh documented session establishment; it must not blindly replay a previous session nonce/session key.
7. If authentication prerequisites are absent or invalid, Capture fails closed with an explicit `Tuya authentication required` state and does **not** start the outdoor scenario sequence.

## Read-only boundary

Until DP semantics and command behavior are physically verified, application writes are authorized **only** when every byte is required by the documented Tuya secure-session/authentication transport. The implementation must not expose a generic raw-write API.

Forbidden in this preflight:

- DP control writes of any kind.
- Lock/unlock, speed-limit, cruise, mode, light, throttle, brake, or power commands.
- Device unbind/reset/factory reset.
- Pairing-mode/reset commands that could remove the device from the user's Tuya account.
- Guessing or brute-forcing auth keys, device secrets, nonces, protocol versions, or command IDs.
- Treating GPS/scenario timing as proof of a Bluetooth DP mapping.

## Credential custody QA

The safest product shape is a dedicated credential/session provider with an API narrower than `writeValue`:

- Input: documented Tuya account/device authorization material obtained through an official Tuya SDK/cloud/account flow.
- Output: an authenticated session object capable only of transport-required authenticated requests and decrypting notifications.
- Secrets remain in memory/Keychain-class storage as appropriate and are redacted from diagnostics.
- Export records only non-secret milestones such as `tuya_auth_started`, `tuya_auth_succeeded`, `tuya_auth_failed`, protocol version if non-secret, elapsed time, and payload counts.

Required adversarial tests before field use:

- wrong/expired credential -> fail closed, no scenario start;
- missing credential -> fail closed, no scenario start;
- authentication timeout -> no reconnect loop that spams authentication indefinitely;
- disconnect during handshake -> discard partial session state;
- reconnect -> new session establishment before accepting notifications as current;
- background/foreground transition during handshake -> no stale completion may authorize the new connection generation;
- logs/export -> no secret, auth key, session key, plaintext credential, or raw access token;
- arbitrary caller cannot invoke the FD50 write characteristic directly.

## Stationary-first follow-up

After the P0 gate passes and real decrypted notifications exist, map stationary states before any outdoor repeat:

1. untouched idle baseline;
2. current Tuya-app battery/odometer values recorded as **operator reference only**;
3. ECO / Drive / Sport, one at a time;
4. light off/on;
5. brake held and brake pulses;
6. optional charger unplugged -> plugged -> unplugged transition while indoors.

Only fields that change repeatably with one controlled state transition may be promoted to candidate DP semantics. Movement/GPS tests happen only after stationary DP evidence is visible.

## Current QA verdict

**Authentication implementation is BLOCKED on official device/account authorization material, not on BLE discovery or reconnect code.** The current passive Capture transport should not be expanded with guessed writes. The correct next code step is an official-Tuya-backed credential/session adapter plus the fail-closed UI gate above.