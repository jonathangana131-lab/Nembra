# Capture — official Tuya SDK provisioning for authenticated read-only preflight

This is the accepted private-SDK path from physical capture `C7D09A22` to the next supported authenticated stationary session. Do not substitute guessed characteristic writes, historical UUID promotion, or hint-based target selection.

## What the user's existing Tuya app account proves

The scooter is already bound and usable in the Tuya app. That establishes account/device ownership context, but Nembra cannot safely copy another iOS app's private session material or treat the Tuya app password as a BLE device key.

The metadata-only Capture flow can also receive the device's cloud `local_key` through the authorized Tuya account/device-sharing API and retains that value only in this iPhone's Keychain. That is useful private device metadata, but **it is not mechanically accepted as FD50 BLE authentication authority**. Tuya's published Bluetooth pairing/security material distinguishes BLE authentication/pairing inputs from the `local_key` returned by device activation/cloud APIs. Until the official SDK establishes the supported BLE session, the saved cloud key must not unlock the authenticated physical preflight.

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

## Exact public SDK dependency provenance

The physical evidence instrument does not float the public SmartLife dependency line. The repository exact-pins:

- `ThingSmartHomeKit` **7.8.0**;
- `ThingSmartBusinessExtensionKit` **7.8.0**.

The bootstrap uses `pod install --repo-update`, not `pod update`, requires a resolved `Podfile.lock`, verifies those reviewed 7.8.0 top-level products, computes the complete lock SHA-256, and writes the non-secret fingerprint under:

```text
LocalSecrets/TuyaRuntime/ResolvedTuyaDependencyProvenance.txt
```

That local provenance file is mode 0600 and must not contain AppKey/AppSecret. Preserve the accepted lock state for a physical evidence build. Do not silently re-resolve or upgrade the SDK immediately before the run.

The app-specific `ThingSmartCryption` and `NembraTuyaPrivateConfig` pods remain local-only. The optional Bluetooth activation/pairing bundles are deliberately not required merely to pass this read-only experiment: Nembra uses the already-bound-device SmartLife connection path, not activation/pairing APIs.

## Public CI versus field workspace

Public CI builds `NembraCapture.xcodeproj` without private pods. That fallback **must** compile fail-closed: `canImport(ThingSmartHomeKit)` / `canImport(NembraTuyaPrivateConfig)` do not jointly authorize the SDK bootstrap there. A green fallback build proves source/project compatibility only; it is not an accepted physical field build.

The real privately provisioned product is:

```text
NembraCapture.xcworkspace
scheme: Nembra Capture
bundle: com.jonathangana131.nembra.capturelearn
```

The field installer builds that workspace and launches it normally. No Tuya secret is supplied in host process arguments or launch environment.

## Implemented fail-closed product authority

`TuyaAuthenticatedReadOnlyPreflight` and `TuyaAuthenticatedReadOnlySessionLedger` own the non-secret authenticated acceptance chronology. The app does not mint acceptance from a local timer or update counter.

### Pre-discovery authority

Before **OFF1** can begin, all of the following must be current:

1. authoritative compiled field-build identity;
2. private Tuya SDK configuration present;
3. official SDK account logged in;
4. exact expected scooter device ID found in the fully loaded owned/shared home membership;
5. that exact-device membership proof leased to the same current SDK account UID.

Login alone is insufficient. Names, RSSI, category, product display similarity, FD50 presence, Tuya manufacturer data, and the historical C7D09A22 CoreBluetooth UUID do not substitute for account/device authority.

### Fresh target authority

Target correlation is now one package-owned `OFF1 → ON1 → OFF2 → ON2` series. Each window uses a fresh CoreBluetooth manager and must earn scan readiness plus the accepted receipt-bounded minimum duration before seal.

The historical C7D09A22 UUID, FD50, Tuya manufacturer data, name, RSSI, and proximity remain descriptive only. They cannot break ties or mint current target identity.

The series must end with exactly one repeatable full CoreBluetooth UUID. None/ambiguous/invalid chronology fails closed. The operator must then explicitly confirm that freshly correlated Bluetooth target for the current attempt. A unique package result is not automatically confirmed and is not permanent scooter identity.

### Authenticated session authority

After explicit target confirmation, exact SDK account/device membership is re-proven immediately before granting Tuya BLE ownership. The Tuya SmartLife SDK is the sole authenticated BLE owner; Nembra does not maintain a competing post-auth CoreBluetooth connection.

The current connection generation then needs all of the following:

1. a supported Tuya session established by the accepted SmartLife SDK route;
2. bounded local-BLE settlement after transport success, with authenticated chronology starting only after Tuya local BLE is actually observed online;
3. explicit `.smartLifeAppSDK` authentication provenance;
4. current same-account exact-device authority throughout the attempt;
5. at least one non-empty `ThingSmartDeviceDelegate.dpsUpdate` received **after authentication in the same ledger generation**;
6. at least 45 seconds of canonical monotonic authenticated observation;
7. no disqualifying observation poll gap or monotonic regression;
8. immutable canonical seal before product success;
9. no Nembra DP query/publish, pairing, activation, reset, unbind, or other scooter control action.

Reconnects/retries cannot reuse retired authority. Stale or cross-ledger callbacks cannot authorize the current generation. An unexpected active package generation must be terminally accounted for before a new OFF1 attempt. Package-already-terminal observation-continuity failures are mirrored into app state exactly once rather than terminalized a second time.

## Application-data truth boundary

The current official SDK callback supplies structured DP/status values. It does **not** expose byte-exact raw FD50 notification frames through this adapter.

Therefore the diagnostic artifact records:

- the application update count and chronology;
- sanitized/string-projected DP keys/values for offline correlation;
- authentication method and connection generation;
- exact current-session target-correlation provenance;
- explicit operator-confirmation state;
- exact membership/local-BLE/preflight verdict metadata;
- exact build identifier/source SHA;
- `rawFD50BytesCaptured: false`;
- `dpQueriesSent: false`;
- `dpCommandsSent: false`.

It must never label an SDK dictionary serialized by Nembra as raw Bluetooth bytes. Raw FD50 transport capture remains a separate evidence problem if later required.

## Remaining external field blocker

The repository cannot manufacture the user's real Tuya Developer Platform app identity or app-specific security SDK. Physical GO therefore still requires the exact private materials for bundle `com.jonathangana131.nembra.capturelearn` to be present locally, the reviewed locked workspace to build/sign/install the exact accepted source on the intended iPhone 12 / iOS 27, and the app's own gates to prove current SDK account authority, exact scooter membership, fresh four-window target correlation, explicit target confirmation, supported authenticated session, genuine same-generation structured application evidence, and the canonical sealed observation horizon.

A public CI green result alone is not physical GO.

## Field sequence after exact-head software acceptance and explicit repository GO

1. Place the matching app-specific `ThingSmartCryption.podspec` + `Build/` under `LocalSecrets/TuyaSDK`.
2. Run `Scripts/provision_capture_tuya_identity.sh` and enter the matching Tuya AppKey/AppSecret locally.
3. Run `Scripts/bootstrap_capture_tuya_sdk.sh`; preserve the resulting reviewed `Podfile.lock` and lock fingerprint.
4. Run `scripts/field/install_one_time_capture.command` with the intended iPhone connected/unlocked, using the exact accepted source/build identity.
5. In Capture, verify authoritative field-build provenance and authorize the official SDK account by verification code if needed.
6. Require fresh exact scooter membership verification under that same current SDK account.
7. Keep the scooter stationary and perform the complete package-owned `OFF1 → ON1 → OFF2 → ON2` correlation. Do not use historical UUID/FD50/Tuya/name/RSSI hints as authority.
8. Require exactly one repeatable full UUID, then explicitly confirm the correlated Bluetooth target for this attempt.
9. Start the secure read-only test only after every pre-auth gate is green. Tuya's SDK becomes the sole authenticated BLE owner.
10. Pass only on current same-account exact-device authority + Tuya local BLE observed online + genuine same-generation non-empty `dpsUpdate` evidence + at least 45 seconds canonical continuity + immutable accepted seal.
11. Prepare/share the sanitized diagnostic JSON. On any failure, stop and preserve only legitimate evidence.

Do **not** repeat the old 17-step outdoor run yet. After this stationary secure-link gate passes, the next experiment should be the smallest stationary DP-correlation sequence justified by the captured data.