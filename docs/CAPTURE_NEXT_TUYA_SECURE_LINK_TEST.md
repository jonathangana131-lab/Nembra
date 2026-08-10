# Nembra Capture — next physical test after C7D09A22

## What C7D09A22 closed

The first real physical artifact identified the scooter transport as Tuya BLE over service `FD50`, with the prior physical CoreBluetooth peripheral ID `6815A5F5-4D1E-E004-BAE8-6DF924123907` and advertising local name `demo`. The 17-step run completed but received zero application characteristic payloads. The connection repeatedly dropped at the unauthenticated timeout window, so repeating the ride sequence before supported Tuya authentication would waste another field run.

## Next test is indoor and stationary

Do **not** repeat the old 17-step calibration.

The next test does only this:

1. Link/read the user's already-bound Tuya device identity.
2. With scooter OFF, collect a short local Bluetooth baseline.
3. Turn the scooter ON and identify it using the previous CoreBluetooth UUID plus FD50 / Tuya company-ID / power-on-delta evidence.
4. Stop Nembra's CoreBluetooth scan before secure authentication starts.
5. Let the official Tuya SmartLife App SDK exclusively own the authenticated BLE connection.
6. Attach a `ThingSmartDeviceDelegate` observer for device application/DP updates. Do not publish/query DPs.
7. Poll only Tuya's local BLE online API to prove continuity.
8. PASS only when the SDK reports the device locally connected for more than 45 seconds and at least one genuine device application update has arrived.
9. Export sanitized diagnostics.

## Safety boundary

This experiment must not:

- turn `local_key` into a guessed BLE session key;
- construct/fuzz raw FD50 authentication frames;
- open a second CoreBluetooth connection after Tuya owns BLE;
- publish or query a DP;
- change lock, speed limit, mode, light, cruise, throttle, brake, firmware, or any scooter setting;
- unbind/remove/reset/factory-reset the scooter;
- assign battery, speed, mode, brake, throttle, light, power, current, voltage, odometer or other semantics to any DP yet.

Opaque DP IDs/values may be recorded only as evidence for the later mapping pass.

## Official Tuya integration gate

The supported iOS path requires Tuya's SmartLife App SDK and the app-specific security material generated for a Tuya Developer Platform iOS app whose Bundle ID matches the Capture target. Tuya's current iOS SDK line uses CocoaPods; the required base SDK is `ThingSmartHomeKit`, and current releases list a Bluetooth extra alongside the base SDK. Tuya's generated security component and AppKey/AppSecret are private and must never be committed to this repository.

The Capture source therefore compiles without Tuya SDK using `#if canImport(ThingSmartHomeKit)`, but the physical **Start secure read-only test** control remains unavailable until all of these are true at runtime:

- `ThingSmartHomeKit` is present in the signed local field build;
- the matching private Tuya security component is present;
- `NEMBRA_TUYA_APP_KEY` and `NEMBRA_TUYA_APP_SECRET` are supplied privately for the local development run;
- `ThingSmartUser` has an authorized SDK account session containing the already-bound scooter.

The secure-link screen now initializes the configured official SDK and exposes Tuya's verification-code **email** login for that SDK account session. Nembra does not request or store the Tuya account password. The email address and one-time code remain transient UI state and are not written into the diagnostic export. This closes the previous fresh-install dead end where `sdkAccountAuthorized` could fail closed but the Capture UI had no supported way to make it true.

The metadata QR session is intentionally not treated as an SDK BLE-authentication session. Phone/SMS verification is not silently substituted for email login because Tuya documents extra region/service requirements for mobile verification; if the user's bound account is phone-only, that becomes a separate explicit preflight blocker rather than a guessed login path.

## Why one BLE owner matters

An earlier scaffold authenticated through the official SDK and then attempted to attach a separate CoreBluetooth connection to read FD50 notifications. That is removed. Tuya's documented `ThingSmartBLEManager` connection and `ThingSmartDeviceDelegate` DP callback now form the sole authenticated observation path, avoiding connection ownership competition.

## Acceptance artifact

Share `Nembra-Secure-Link-*-Diagnostics.json` after the test. It includes identification evidence, gate states, local-BLE continuity, application-update count, opaque update values and failures. It excludes AppSecret, account tokens, passwords and `local_key`.

If this secure-link test passes, the next run is a short **stationary DP mapping** sequence (idle, modes, light, brake, optional charger transition). Movement/GPS tests remain blocked until stationary DPs are visible and repeatable.
