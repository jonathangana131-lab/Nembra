# Capture — official Tuya SDK provisioning for authenticated read-only preflight

This is the accepted route from physical capture `C7D09A22` toward an authenticated Tuya BLE session. Do not substitute guessed characteristic writes or guessed FD50 authentication frames.

## What the user's existing Tuya app account proves

The scooter is already bound and usable in the Tuya app. That establishes account/device ownership context, but Nembra cannot safely copy another iOS app's private session material or treat the Tuya app password as a BLE device key.

The metadata-only Capture flow can also receive the device's cloud `local_key` through the authorized Tuya account/device-sharing API and retains that value only in this iPhone's Keychain. That is useful private device metadata, but **it is not mechanically accepted as FD50 BLE authentication authority**. The saved cloud key must not unlock the authenticated physical preflight.

## Private SDK material

Tuya's SmartLife App SDK integration requires an SDK-based app created on the Tuya Developer Platform with a matching iOS Bundle ID, its AppKey/AppSecret, and the app-specific security SDK generated for that exact Tuya app identity.

For the current integration, the downloaded iOS security package supplies:

- `Build/` — the private security SDK specific to the app;
- `ThingSmartCryption.podspec` — the CocoaPods integration point for that security SDK.

Nembra's repository intentionally does not and must not contain those files. The local integration contract is:

```text
LocalSecrets/TuyaSDK/
├── Build/
└── ThingSmartCryption.podspec
```

`LocalSecrets/` is git-ignored. `Podfile` references `ThingSmartCryption` from that private path plus the pinned SmartLife 7.8.x SDK dependencies. `Scripts/bootstrap_capture_tuya_sdk.sh` fails before dependency resolution when either private security-SDK component is absent.

The repository must never commit a real AppSecret, private AppKey provisioning value, user password, access token, device key, session key, nonce, downloaded `Build/` security SDK, or decrypted credential artifact. User login occurs through Tuya's supported SDK verification-code flow, not through custom password capture.

## Public SDK dependency boundary

The branch currently pins:

- `ThingSmartHomeKit`;
- `ThingSmartBusinessExtensionKit`;
- local-only `ThingSmartCryption`.

Pairing/activation bundles are not added merely to pass this observation experiment. Nembra uses the already-bound-device path and does not activate, pair, unbind, reset, or mutate the scooter.

## Private AppKey/AppSecret launch custody

`NembraCaptureEntrypoint.swift` reads `NEMBRA_TUYA_APP_KEY` and `NEMBRA_TUYA_APP_SECRET` from the launched app's process environment. Those values are private runtime provisioning material.

The field helper **must not** receive them and **must not** place them in `devicectl` command arguments. The rejected launcher serialized them into a literal `devicectl --environment-variables` argument, which exposed the values through the host process argument vector. That path is removed and is not an accepted field authority.

For the private local development run, use Xcode's Run-scheme environment-variable support:

1. run `scripts/field/install_one_time_capture.command` to validate the exact flagship branch, private SDK package, workspace, signing identity and intended connected iPhone;
2. keep `NembraCapture.xcworkspace` open in Xcode;
3. select the intended iPhone as the Run destination;
4. duplicate the shared `Nembra Capture` scheme to a clearly named field scheme such as `Nembra Capture Private Field`;
5. make the duplicate **personal / not shared** so it remains local user state rather than repository state;
6. in **Edit Scheme > Run > Arguments > Environment Variables**, add enabled `NEMBRA_TUYA_APP_KEY` and `NEMBRA_TUYA_APP_SECRET`;
7. enter those values only in Xcode — not in Terminal, shell history, Git, the helper, issue/PR text, console output, or Capture diagnostics;
8. Run the personal scheme from Xcode on the intended iPhone;
9. after the stationary test, disable/remove both entries and delete the personal field scheme.

The repository already ignores `xcuserdata/`, and the generated CocoaPods workspace is also ignored. That prevents ordinary per-user scheme state from becoming a Git artifact, but it does **not** make a local secret-bearing scheme permanent-safe storage. Keep it only as long as needed for the private test.

This Xcode launch handoff supplies credentials to the app without turning them into app command-line arguments. It is still only a provisioning mechanism: it does not prove SDK login, exact scooter membership, BLE authentication, accepted observation duration, or application data.

## Implemented fail-closed product authority

`NembraBluetoothCapture/TuyaAuthenticatedReadOnlyPreflight.swift` defines the canonical non-secret acceptance verdict through the narrow `TuyaReadOnlyAuthenticationSessionProvider` boundary. It does not expose generic `writeValue`, DP publish/query, control, unbind, reset, or pairing-reset operations.

The current acceptance contract requires one authenticated connection generation with all of the following:

1. an accepted official Tuya authentication method;
2. SDK identity/configuration present;
3. current SDK account authority;
4. current local-BLE online authority;
5. **at least 45 seconds** of canonical monotonic authenticated observation;
6. at least one genuine non-empty application update admitted for the same authentication generation;
7. no command/control activity admitted by the read-only preflight.

A stale-generation payload, missing SDK/security provisioning, stale/failed account authority, missing exact-device authority, lost local BLE, a long invalid observation gap, zero application updates, or insufficient duration remains fail-closed.

The SDK application/DP callback is application-level evidence. It is **not raw FD50 characteristic bytes**. Do not describe its values as byte-exact transport capture.

## Current remaining software gates before physical GO

Private provisioning is no longer solved by passing secrets through a command-line launcher. The personal Xcode Run scheme is the private runtime handoff, but physical execution still remains **NO-GO** until the exact current product head closes all app-authority/privacy red gates and receives required exact-head software acceptance.

In particular, before the first scooter-OFF CoreBluetooth scan, the final app must mechanically require current official SDK account + exact scooter membership authority; UI convention alone is insufficient. Tuya SDK failure text must also be scrubbed before account identifiers or other private values can reach UI/logging.

When those exact-head gates are accepted, the first user experiment remains one indoor/stationary authentication test. Do not repeat the old outdoor 17-step ride capture.
