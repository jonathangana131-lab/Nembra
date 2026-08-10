# Capture — official Tuya SDK bootstrap for C7D09A22

Status: P0 implementation handoff for the next **stationary** authenticated read-only test.

This document does not authorize another outdoor ride and does not authorize guessed Tuya frames or scooter control writes.

## Physical starting point

Physical capture `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E` already established:

- Tuya BLE service `FD50`;
- write characteristic `00000001-0000-1001-8001-00805F9B07D0`;
- notify characteristic `00000002-0000-1001-8001-00805F9B07D0`;
- notification subscription succeeds;
- application payload count remained `0`;
- the peripheral repeatedly disconnected at about `29.93 s` while Nembra had not completed Tuya application-layer authentication.

The next experiment therefore proves only authenticated session establishment and notification delivery.

## Exact Capture app identity

The standalone project is:

- project: `NembraCapture.xcodeproj`;
- target: `Nembra Capture`;
- bundle identifier: `com.jonathangana131.nembra.capturelearn`;
- deployment target: iOS 17 or later;
- physical baseline: iPhone 12 / iOS 27.

The Tuya Developer Platform iOS SDK app must use that exact bundle identifier. A security package generated for a different app/bundle is not accepted.

## Repository dependency bootstrap

The root `Podfile` pins the SmartLife iOS SDK family used by this experiment and includes the Bluetooth extension required for BLE devices.

Tuya App SDK v5 and later requires an app-specific security package. Download the security SDK for the exact Tuya Developer Platform app, then keep the extracted material **only on the private development Mac** under:

`.tuya-private-sdk/`

That ignored directory must contain the generated `ThingSmartCryption.podspec` and its matching `Build` payload in the layout supplied by Tuya.

Then run CocoaPods on the private development Mac and open the generated `NembraCapture.xcworkspace`, not the bare `.xcodeproj`, for SDK-backed builds.

Do not copy the generated Tuya security SDK into GitHub, an issue, PR, chat attachment, capture JSON, screenshot, or diagnostic artifact.

## App credentials

The matching Tuya Developer Platform AppKey/AppSecret must be injected only on the private development/build surface.

Do not commit a real:

- AppSecret;
- AppKey/AppSecret pair;
- account password;
- access token;
- refresh token;
- device `local_key`;
- auth/session key;
- nonce;
- generated Tuya security package.

Nembra may keep the selected already-bound device's `local_key` in the iPhone Keychain only for this private research flow. The redacted metadata export must continue excluding it.

The Keychain writer on this branch is fail-closed:

- selecting a device with no `local_key` clears an older selected credential instead of silently leaving stale material behind;
- replacement updates the existing Keychain item in place rather than delete-then-add;
- a Keychain failure is surfaced as a blocker for the secure Bluetooth test.

## SDK adapter boundary

When the private SDK is present, the next code slice must use Tuya's supported existing-device BLE connection/session APIs for the already-bound device identity. It must not implement Tuya encryption or challenge packets by guessing.

The adapter may expose only the capability required by `TuyaReadOnlyAuthenticationSessionProvider`:

- current non-secret authentication state;
- current connection generation;
- monotonic authenticated-session timing;
- count of non-empty application notifications.

It must not expose a generic GATT write API or a generic DP-control API to the Capture UI.

A reconnect starts a fresh documented Tuya session establishment. Old nonce/session-key state cannot authorize a new CoreBluetooth connection generation.

## Stationary physical acceptance

The first SDK-backed field run stays indoors and stationary.

Accepted only when the same authenticated connection generation has:

1. documented Tuya authentication for the user's already-bound device;
2. at least one non-empty application notification payload; and
3. at least `45 s` of authenticated connection survival.

If credentials/security SDK are absent, authentication fails, notifications remain empty, or the old ~30-second rejection repeats, fail closed and stop.

Do not start the old 17-step outdoor calibration.

## Export boundary for the auth experiment

The diagnostic artifact may contain:

- transport family `tuya-fd50`;
- non-secret auth method/result;
- connection generation;
- authenticated duration;
- application notification count;
- notification receipt time;
- characteristic UUID;
- raw encrypted/application payload bytes needed for offline protocol analysis, provided they are not credential/session material;
- explicit redaction markers.

It must not contain account credentials, cloud tokens, AppSecret, local/session/auth keys, QR authorization tokens, or plaintext secrets.

## Next rung after acceptance

Only after the authenticated gate passes should Nembra run a small stationary correlation sequence: idle baseline, operator-recorded Tuya battery/odometer reference, one mode change at a time, light off/on, brake state, and optionally charger unplugged/plugged/unplugged.

Movement/GPS correlation remains later. No DP meaning is promoted until repeatable physical evidence supports it.
