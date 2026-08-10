# Capture — official Tuya SDK provisioning for authenticated read-only preflight

This is the only accepted path from physical capture `C7D09A22` to an authenticated FD50 session. Do not substitute guessed characteristic writes.

## What the user's existing Tuya app account proves

The scooter is already bound and usable in the Tuya app. That establishes account/device ownership context, but Nembra cannot safely copy another iOS app's private session material or treat the Tuya app password as a BLE device key.

The metadata-only Capture flow can also receive the device's cloud `local_key` through the authorized Tuya account/device-sharing API and retains that value only in this iPhone's Keychain. That is useful private device metadata, but **it is not mechanically accepted as FD50 BLE authentication authority**. Tuya's published Bluetooth pairing/security material distinguishes BLE authentication/pairing inputs from the `local_key` returned by device activation/cloud APIs. Until an official SDK or other documented Tuya route establishes the BLE session, the saved cloud key must not unlock the authenticated physical preflight.

## Required private Tuya app material

Tuya's official SmartLife App SDK integration requires an SDK-based app created on the Tuya Developer Platform with a matching iOS Bundle ID, its AppKey/AppSecret, and the app-specific security SDK generated for that exact Tuya app identity.

For the current SmartLife iOS SDK integration, Tuya's downloaded `ios_core_sdk.tar.gz` supplies:

- `Build/` — the private security SDK specific to the app;
- `ThingSmartCryption.podspec` — the CocoaPods integration point for that security SDK.

Nembra's repository intentionally does not and must not contain those files. The local security-SDK contract is:

```text
LocalSecrets/TuyaSDK/
├── Build/
└── ThingSmartCryption.podspec
```

The matching AppKey/AppSecret are also not accepted through Git, Xcode build arguments, `devicectl --environment-variables`, process arguments, or diagnostic exports. The reviewed local field-build channel is:

```text
LocalSecrets/TuyaRuntime/
├── NembraTuyaPrivateConfig.podspec
└── Sources/
    └── NembraTuyaPrivateConfig/
        └── NembraTuyaPrivateIdentity.swift
```

Generate that local-only pod with:

```sh
Scripts/provision_capture_tuya_identity.sh
```

The script reads AppKey/AppSecret with terminal echo disabled, uses restrictive local file permissions, and writes only beneath git-ignored `LocalSecrets/`. The generated Swift source base64-encodes the values only so arbitrary credential characters can be represented safely as generated source; this is **not encryption** and is not claimed as secret-at-rest protection. The app binary necessarily receives the app identity in process because Tuya's SDK initialization contract requires it.

`Scripts/bootstrap_capture_tuya_sdk.sh` fails before dependency resolution unless both the app-specific Cryption package and local private identity pod are present. `Podfile` consumes both private local pods only in the CocoaPods field workspace.

The repository must never commit a real AppSecret, AppKey, user password, access token, device key, session key, nonce, downloaded `Build/` security SDK, generated private identity pod, or decrypted credential artifact. User login occurs through Tuya's supported verification-code SDK flow; Capture does not collect the Tuya account password.

## Public CI versus field workspace

The branch uses the current Tuya public pod source and pins the SmartLife 7.8.x line for:

- `ThingSmartHomeKit`;
- `ThingSmartBusinessExtensionKit`.

The app-specific `ThingSmartCryption` and `NembraTuyaPrivateConfig` pods are local-only. The optional Bluetooth activation/pairing bundles are deliberately not required merely to pass this read-only experiment: Tuya documents `ThingSmartBLEManager` on the SmartLife SDK path, including connecting an already activated/offline BLE device by its UUID and product ID. Nembra uses the already-bound-device connection path, not activation/pairing APIs.

Public CI builds `NembraCapture.xcodeproj` without private pods. That fallback **must** compile fail-closed: `canImport(ThingSmartHomeKit)` / `canImport(NembraTuyaPrivateConfig)` do not jointly authorize the SDK bootstrap there. A green fallback build proves source/project compatibility only; it is not an accepted physical field build.

The real privately provisioned product is:

```text
NembraCapture.xcworkspace
scheme: Nembra Capture
bundle: com.jonathangana131.nembra.capturelearn
```

The field installer builds that workspace and launches it normally. No Tuya secret is supplied in host process arguments or launch environment.

## Implemented fail-closed product authority

`TuyaAuthenticatedReadOnlyPreflight` and `TuyaAuthenticatedReadOnlySessionLedger` own the non-secret acceptance chronology. The app does not mint acceptance from a local timer or update counter.

Before Bluetooth authentication can start, the official SDK account must be logged in and `TuyaSDKAccountDeviceMembershipGate` must find the **exact expected scooter device ID** in the fully loaded owned/shared home membership. SDK login alone is insufficient; names, RSSI, category, and display similarity do not substitute for exact device membership.

The current connection generation then needs all of the following:

1. an authenticated Tuya session established by the accepted SmartLife SDK route;
2. explicit `.smartLifeAppSDK` authentication provenance;
3. Tuya reporting the expected device locally BLE-connected;
4. at least one non-empty `ThingSmartDeviceDelegate.dpsUpdate` received **after authentication in the same ledger generation**;
5. at least 45 seconds of canonical monotonic authenticated observation;
6. no observation poll gap longer than the accepted field continuity bound;
7. no DP command, pairing, activation, reset, unbind, or other control action.

Reconnects reset evidence. Stale or cross-ledger callbacks cannot authorize the current generation.

## Application-data truth boundary

The current official SDK callback supplies structured DP/status values. It does **not** expose byte-exact raw FD50 notification frames through this adapter.

Therefore the diagnostic artifact records:

- the application update count and chronology;
- sanitized/string-projected DP keys/values for offline correlation;
- authentication method and connection generation;
- exact membership/local-BLE/preflight verdict metadata;
- `rawFD50BytesCaptured: false`.

It must never label an SDK dictionary serialized by Nembra as raw Bluetooth bytes. Raw FD50 transport capture remains a separate evidence problem if later required.

## Remaining external field blocker

The repository has the software path for private local provisioning, but it cannot manufacture the Tuya Developer Platform app identity or app-specific security SDK. Physical GO therefore still requires the exact private materials for bundle `com.jonathangana131.nembra.capturelearn` to be present locally, the workspace to build/sign/install on the real iPhone, and the app's own gates to prove the expected scooter membership and authenticated session.

A public CI green result alone is not physical GO.

## Field sequence after exact-head software acceptance

1. Place the matching app-specific `ThingSmartCryption.podspec` + `Build/` under `LocalSecrets/TuyaSDK`.
2. Run `Scripts/provision_capture_tuya_identity.sh` and enter the matching Tuya AppKey/AppSecret locally.
3. Run `scripts/field/install_one_time_capture.command` with the iPhone connected/unlocked.
4. In Capture, authorize the official SDK account by verification code if needed.
5. Require exact scooter membership verification.
6. Keep the scooter stationary; perform the OFF baseline then ON correlation.
7. Start the secure read-only test only when every pre-BLE gate is green.
8. Pass only on same-generation `dpsUpdate` evidence + Tuya local BLE online + at least 45 seconds canonical continuity.
9. On any failure, export/share the sanitized diagnostic JSON and stop.

Do **not** repeat the old 17-step outdoor run yet. After this stationary secure-link gate passes, the next experiment should be the smallest stationary DP-correlation sequence justified by the captured data.