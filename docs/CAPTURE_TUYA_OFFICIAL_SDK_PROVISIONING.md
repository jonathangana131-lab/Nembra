# Capture — official Tuya SDK provisioning for authenticated read-only preflight

This is the only accepted path from physical capture `C7D09A22` to an authenticated FD50 session. Do not substitute guessed characteristic writes.

## What the user's existing Tuya app account proves

The scooter is already bound and usable in the Tuya app. That establishes account/device ownership context, but Nembra cannot safely copy another iOS app's private session material or treat the Tuya app password as a BLE device key.

The metadata-only Capture flow can also receive the device's cloud `local_key` through the authorized Tuya account/device-sharing API and retains that value only in this iPhone's Keychain. That is useful private device metadata, but **it is not mechanically accepted as FD50 BLE authentication authority**. Tuya's published Bluetooth pairing/security material distinguishes BLE authentication/pairing inputs from the `local_key` returned by device activation/cloud APIs. Until an official SDK or other documented Tuya route establishes the BLE session, the saved cloud key must not unlock the authenticated physical preflight.

## What Nembra still needs

Tuya's official SmartLife App SDK integration requires an SDK-based app created on the Tuya Developer Platform with a matching iOS Bundle ID, its AppKey/AppSecret, and the app-specific security SDK generated for that exact Tuya app identity.

For current SmartLife iOS SDK integration, Tuya's downloaded `ios_core_sdk.tar.gz` contains:

- `Build/` — the private security SDK specific to the app;
- `ThingSmartCryption.podspec` — the CocoaPods integration point for that security SDK.

Nembra's repository intentionally does not and must not contain those files. The local integration contract is:

```text
LocalSecrets/TuyaSDK/
├── Build/
└── ThingSmartCryption.podspec
```

`LocalSecrets/` is git-ignored. `Podfile` references `ThingSmartCryption` from that private path and the public SmartLife 7.8.0 SDK line. `Scripts/bootstrap_capture_tuya_sdk.sh` fails before dependency resolution when either private security-SDK component is absent.

The repository must never commit a real AppSecret, AppKey when it is treated as private provisioning material, user password, access token, device key, session key, nonce, downloaded `Build/` security SDK, or decrypted credential artifact. User login should occur through Tuya's supported SDK/account flow, not through a custom password capture added to Capture.

## Current public SDK dependency boundary

The branch uses the current Tuya public pod source and pins the current SmartLife 7.8.x line for:

- `ThingSmartHomeKit`;
- `ThingSmartBusinessExtensionKit`.

The app-specific `ThingSmartCryption` pod is local-only. The optional Bluetooth extension/pairing bundles are deliberately not required merely to pass this read-only experiment: Tuya documents `ThingSmartBLEManager` on the SmartLife SDK path, including connecting an already activated/offline BLE device by its UUID and product ID. Nembra must use the already-bound-device connection path, not activation/pairing APIs.

## Implemented fail-closed product seam

`NembraBluetoothCapture/TuyaAuthenticatedReadOnlyPreflight.swift` defines the non-secret acceptance gate and a deliberately narrow `TuyaReadOnlyAuthenticationSessionProvider` protocol. It does not expose generic `writeValue`, DP control, unbind, reset, or pairing-reset operations.

`TuyaAuthenticatedReadOnlyPreflightSnapshot` carries `TuyaReadOnlyAuthenticationMethod?`. An `.authenticated` state without accepted official method provenance fails closed before payload or duration can unlock anything. The cloud `local_key` is intentionally not an authentication method.

Stationary mapping is unlocked only when one connection generation has:

1. an authenticated Tuya session established by an accepted official route;
2. explicit accepted authentication-method provenance;
3. at least one non-empty application payload; and
4. at least 45 seconds of authenticated connection survival.

Missing SDK/security-package provisioning, failed authentication, missing provenance, zero payloads, or insufficient survival time remain fail-closed.

## Current external provisioning blocker

The repository can build and test the fail-closed contract without secrets, but it cannot manufacture Tuya's app-specific security SDK or app credentials. Route A still requires a Tuya Developer Platform SmartLife App SDK configuration whose iOS Bundle ID exactly matches the Capture app, then a locally extracted `ios_core_sdk.tar.gz` and privately supplied app credentials for that same app identity.

A public CocoaPods resolution of `ThingSmartHomeKit` alone is **not** a provisioned Tuya application and must never authorize the physical test.

## Next integration step

After the exact app-specific security SDK and credentials are privately provisioned:

1. integrate dependencies through `NembraCapture.xcworkspace`;
2. initialize the official Tuya SDK with the matching app identity;
3. authorize the user's own Tuya SDK account/session;
4. locate the already-bound scooter from that authorized device model;
5. use Tuya's documented already-activated/offline BLE connection path with the device UUID + product ID;
6. adapt only authenticated connection/notification evidence into `TuyaReadOnlyAuthenticationSessionProvider`;
7. export non-secret raw application payload receipts for offline analysis;
8. expose no generic DP write/control API.

Do not start another outdoor ride to test this. The first accepted physical run is stationary and needs accepted official authentication provenance, one real application payload, and at least 45 seconds of authenticated connection continuity.
