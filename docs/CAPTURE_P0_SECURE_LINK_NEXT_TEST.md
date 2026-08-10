# Nembra Capture P0 — secure-link gate

This is the continuation after capture `C7D09A22`. Do not repeat the completed 17-step ride capture.

## What is already proven

- The scooter is Tuya BLE family and exposes service `FD50`.
- The known CoreBluetooth peripheral from the first capture was `6815A5F5-4D1E-E004-BAE8-6DF924123907`.
- FD50 write characteristic `00000001-0000-1001-8001-00805F9B07D0` and notify characteristic `00000002-0000-1001-8001-00805F9B07D0` were observed.
- Notifications could be subscribed at the GATT level, but no application characteristic-value frames arrived.
- The first run repeatedly disconnected around 30 seconds because the required Tuya application session was not established.
- No DP mapping may be inferred from that capture.

## Current gate

Nembra Capture must establish the supported Tuya session for the already-bound scooter before any DP/control experiment.

The secure-link screen is intentionally fail-closed. The physical test button is disabled until all three of these are true:

1. `ThingSmartHomeKit` is compiled into the standalone Capture target.
2. Private app configuration is supplied at runtime with `NEMBRA_TUYA_APP_KEY` and `NEMBRA_TUYA_APP_SECRET`.
3. `ThingSmartUser.sharedInstance()?.isLogin == true`, meaning the official Tuya SDK itself has an authorized account session.

The existing metadata/ownership QR bridge is not treated as the SDK login session and `local_key` is not used as a guessed BLE login key.

## Tuya SDK provisioning — non-physical prerequisite

Create/build a SmartLife App SDK app on the Tuya Developer Platform for the exact Capture bundle identifier used by `NembraCapture.xcodeproj` and download its app-specific iOS security component. Integrate the official `ThingSmartHomeKit` dependency together with the matching `ThingSmartCryption` component required by the generated SDK package.

Keep the AppKey/AppSecret out of Git. For local Xcode runs, put them in the scheme's Run environment only:

- `NEMBRA_TUYA_APP_KEY`
- `NEMBRA_TUYA_APP_SECRET`

Do not paste credentials into source, build logs, screenshots, issues, or exported Capture JSON.

The official SDK account must then be authorized for the same bound scooter/home. If QR-based SDK login is used, the Tuya SDK app must have the required Tuya allowlisting for that login mode. Do not substitute the Home Assistant-style metadata authorization token for the App SDK's own login state.

## Smallest physical test — only after the three SDK gates are green

This test stays indoors and stationary.

1. Keep the scooter **OFF** and tap **Start scooter-OFF baseline**.
2. After a few seconds tap **Save OFF baseline**.
3. Turn the scooter **ON** and leave it stationary.
4. Tap **Scan after power-on** and then **Stop scan / use best evidence**.
5. Capture ranks the likely scooter using the known first-capture UUID, FD50 advertisement evidence, Tuya manufacturer company ID `0x07D0`, OFF→ON appearance delta, expected local-name evidence, and RSSI/proximity. Do not guess among unnamed peripherals.
6. Confirm the highlighted **LIKELY SCOOTER** candidate and tap **Start secure read-only test**.
7. Do nothing to the scooter. Capture delegates the secure connection to Tuya's SDK, then passively subscribes to FD50 notify `0002` and counts raw post-auth frames.
8. Acceptance requires both:
   - secure-session age greater than 45 seconds, and
   - at least one genuine post-auth FD50 notification frame.

On pass, the UI shows **Secure scooter link established** and **Receiving scooter data**.

On failure, tap **Prepare sanitized diagnostic JSON** and share that file. It contains candidate evidence, timing, failure state, and any post-auth raw notification bytes. It does not export Tuya passwords, account access/refresh tokens, `local_key`, AppSecret, or scooter DP/control writes.

## Safety boundary

For this P0 gate Nembra itself sends no lock, unlock, reset, unbind, speed-limit, light, mode, throttle, brake, motor, firmware, or other scooter DP/control command. Any Bluetooth traffic required to establish the supported Tuya session is owned by the official Tuya SDK.

Do not proceed to DP mapping until this gate passes. After it passes, the next experiment should be the smallest stationary mapping sequence: idle baseline, light off/on, ECO/Drive/Sport, brake, and optional charger state. Motion-only values such as speed/odometer/power behavior belong in a later outdoor test.