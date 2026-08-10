# Nembra Capture — next physical test after C7D09A22

## What C7D09A22 closed

The first real physical artifact identified the scooter transport as Tuya BLE over service `FD50`, with prior physical CoreBluetooth peripheral ID `6815A5F5-4D1E-E004-BAE8-6DF924123907` and advertising local name `demo`.

The 17-step run completed, but it received zero application characteristic payloads and repeatedly lost the peripheral around the unauthenticated timeout window. Repeating that ride sequence before supported Tuya authentication would not answer the current blocker.

## Next test is indoor and stationary

**Do not repeat the old 17-step ride calibration.**

The next physical experiment exists only to prove the supported secure session and collect the first admissible application-level evidence from the already-bound scooter.

1. Build/install the privately provisioned standalone Capture app whose Tuya app identity matches the Capture bundle ID.
2. Log in to the user's own account through Tuya's official SmartLife SDK verification-code flow.
3. Require the official SDK account/home enumeration to find the exact expected scooter device ID. SDK login alone is not device authority.
4. With the scooter OFF, collect a short CoreBluetooth baseline.
5. Turn the scooter ON and correlate the target. Authorization requires either the previously observed physical CoreBluetooth UUID or corroborating `FD50` + Tuya company `0x07D0` evidence. Name, RSSI, and OFF→ON appearance may rank candidates but may not authorize one.
6. Stop Nembra's CoreBluetooth scan before secure authentication begins.
7. Let `ThingSmartBLEManager` exclusively own the authenticated BLE connection. Nembra must not open a second CoreBluetooth connection.
8. Treat the SDK connect callback only as transport progress. Authentication chronology begins only when Tuya's local-BLE status reports this scooter current on the official SDK connection.
9. Admit only non-empty `ThingSmartDeviceDelegate` `dpsUpdate` callbacks from that same sealed connection generation.
10. Keep observing local BLE. A long observation-loop gap or observed local-BLE drop invalidates the generation rather than silently counting toward the timer.
11. PASS only when the canonical `TuyaAuthenticatedReadOnlyPreflight` verdict accepts the generation: official SmartLife authentication provenance, at least one admitted same-generation application update, valid monotonic chronology, and at least 45 seconds of admitted local-BLE observation.
12. Export and share `Nembra-Secure-Link-*-Diagnostics.json`.

## What the application update is — and is not

For this experiment, `ThingSmartDeviceDelegate` delivers structured application/DP updates. Those updates are evidence that the authenticated SDK session is carrying application-level scooter state.

They are **not** claimed to be byte-exact or raw `FD50` notification frames. Capture records the event/provenance needed for chronology and offline analysis while keeping `rawFD50BytesCaptured` false. Do not JSON-serialize a structured SDK dictionary merely to manufacture fake transport bytes.

No DP ID or value has verified scooter semantics yet.

## Safety boundary

This experiment must not:

- turn cloud `local_key` into a guessed BLE session key;
- construct, replay, fuzz, or guess raw `FD50` authentication frames;
- open a second CoreBluetooth connection after Tuya owns BLE;
- publish/query a DP merely to create traffic;
- change lock, speed limit, mode, light, cruise, throttle, brake, firmware, calibration, or any scooter setting;
- unbind, remove, reset, factory-reset, activate, or re-pair the scooter;
- assign battery, speed, mode, brake, throttle, light, power, current, voltage, odometer, regen, or other semantics to an opaque update yet.

## Official Tuya integration gate

A public/fallback build is not enough to authorize the physical test. The signed field build must have all of the following:

- `ThingSmartHomeKit` present;
- the matching app-specific Tuya security component present locally;
- private AppKey/AppSecret supplied for the same Tuya Developer Platform iOS app identity as the Capture bundle;
- an official SDK account login;
- exact membership of the expected scooter device ID proven from that SDK account's owned/shared home devices.

The earlier metadata QR authorization and retained cloud `local_key` remain useful provisioning/account metadata, but neither is BLE-authentication authority.

## PASS / FAIL

### PASS

The diagnostic artifact shows one sealed connection generation with:

- exact SDK account/device membership verified;
- accepted SmartLife SDK authentication provenance;
- local BLE observed current before the authentication timestamp is minted;
- at least one non-empty same-generation `dpsUpdate` admitted after authentication;
- at least 45 seconds of admitted monotonic observation;
- no observation-loop gap beyond the accepted bound;
- no observed local-BLE drop;
- `dpCommandsSent: false`;
- `rawFD50BytesCaptured: false` unless a future documented same-session raw-transport hook earns a different claim.

### FAIL / STOP

Stop and share the diagnostic JSON if any of these occur:

- SDK/security provisioning is missing;
- SDK login or exact scooter membership fails;
- the target cannot be correlated authoritatively;
- Tuya's supported BLE connect fails;
- local BLE never becomes current;
- local BLE drops;
- the observation loop is interrupted long enough to invalidate continuity;
- no admissible application update arrives;
- the canonical preflight remains blocked.

Do not automatically retry forever and do not fall back to the old outdoor ride.

## After this passes

Only after this secure-link gate passes should Nembra generate the next smallest experiment: a short **stationary DP-mapping** sequence such as idle -> confirmed mode changes -> light -> brake -> optional charger transition.

Movement/GPS/speed/power correlation remains blocked until stationary application values are visible, repeatable, and physically mapped without guessing.
