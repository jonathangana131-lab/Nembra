# Capture — official Tuya SDK provisioning for authenticated read-only preflight

This is the accepted route from physical capture `C7D09A22` to the next supported Tuya BLE experiment. Do not substitute guessed characteristic writes or copied credentials from another app.

## Existing evidence does not equal BLE authority

The scooter is already bound and usable in the user's Tuya app. The metadata Capture flow also obtained the device's cloud `local_key` and can retain it privately in this iPhone's Keychain.

Those facts establish useful account/device provisioning context, but **neither the stock-app session nor cloud `local_key` is accepted FD50 BLE-authentication authority for Nembra**. The secure-link test remains locked until Tuya's official SmartLife SDK establishes the supported session for Nembra's own app identity.

## Private app identity required

The SmartLife App SDK integration requires a Tuya Developer Platform SDK app whose iOS Bundle ID matches the standalone Capture target, plus the credentials/security component generated for that exact app identity.

For the current local layout, extract Tuya's private iOS security SDK so the checkout contains:

```text
LocalSecrets/TuyaSDK/
├── Build/
└── ThingSmartCryption.podspec
```

`LocalSecrets/` is git-ignored. The repository must never commit:

- AppSecret;
- private AppKey provisioning material;
- the downloaded `Build/` security SDK;
- user password;
- verification code;
- access/refresh token;
- cloud `local_key`;
- BLE/session/auth key;
- nonce or decrypted credential artifact.

The public CocoaPods dependencies alone do **not** constitute a provisioned Tuya app.

## Repository integration boundary

The Capture Podfile uses:

- local `ThingSmartCryption` from `LocalSecrets/TuyaSDK`;
- the pinned SmartLife public SDK line for `ThingSmartHomeKit`;
- the accompanying public business extension dependency used by the current workspace integration.

`Scripts/bootstrap_capture_tuya_sdk.sh` fails closed when the private security component is absent. Public CI intentionally builds the standalone fallback without `ThingSmartHomeKit`; that proves fail-closed source/project wiring only, not the private SDK build or physical scooter session.

The privately provisioned field build is expected to be opened/built through `NembraCapture.xcworkspace` after CocoaPods integration.

## Current app-visible authority path

The standalone field app already contains the product seam needed after private provisioning:

1. initialize `ThingSmartSDK` with the privately supplied matching AppKey/AppSecret;
2. log in through Tuya's official verification-code account flow rather than collecting a reusable password;
3. enumerate the logged-in account's homes and require the exact expected scooter device ID in owned/shared membership through `TuyaSDKAccountDeviceMembershipGate`;
4. use CoreBluetooth only for passive target discovery/correlation;
5. stop CoreBluetooth discovery before authentication;
6. let `ThingSmartBLEManager` exclusively own the supported already-bound BLE connection;
7. mint authenticated chronology only once Tuya reports the scooter locally BLE-current;
8. admit non-empty `ThingSmartDeviceDelegate` `dpsUpdate` callbacks through `TuyaAuthenticatedReadOnlySessionLedger` for the same opaque connection token/generation;
9. advance liveness only while local BLE remains observed current and the observation loop remains within the accepted gap bound;
10. let `TuyaAuthenticatedReadOnlyPreflight.verdict(for:)` make the final pass/blocked decision.

No generic CoreBluetooth write, DP command, pairing/reset, or unbind API belongs in this preflight path.

## Structured SDK updates are not raw FD50 bytes

The official SDK callback used by this experiment is a structured application/DP dictionary. The ledger admits only whether a non-empty current-generation application update occurred.

Nembra must not serialize that dictionary merely to create fake `Data` and must not label it raw/byte-exact `FD50` transport evidence. The diagnostic export keeps that distinction explicit with `rawFD50BytesCaptured: false`.

If a future documented Tuya SDK hook exposes raw transport bytes from the **same authenticated SDK-owned session**, that can be evaluated separately. A second Nembra-owned CoreBluetooth connection is not an acceptable substitute.

## Current external blocker

The public repository can build/test the fail-closed product and authority contracts, but it cannot manufacture the app-specific Tuya security SDK or matching private credentials.

Before the physical button can legitimately unlock on the intended iPhone, a local/private build still needs:

- a Tuya Developer Platform SmartLife SDK app whose iOS Bundle ID exactly matches `com.jonathangana131.nembra.capturelearn`;
- that app's generated iOS security SDK under `LocalSecrets/TuyaSDK`;
- matching private AppKey/AppSecret supplied to the local build/run environment;
- a signed install on the intended iPhone;
- official SDK verification-code login to the user's account;
- exact expected scooter membership proven from that SDK account.

Do not commit or paste the real secrets into GitHub, diagnostics, screenshots, or chat logs.

## Physical acceptance after provisioning

Private provisioning is only the entrance gate. It does not itself prove ES80 authentication.

The first accepted physical run remains stationary and must earn all of the following in one sealed connection generation:

- exact account/device membership;
- accepted `.smartLifeAppSDK` provenance;
- local BLE observed current before authentication is promoted;
- at least one non-empty post-auth structured SDK application update;
- valid monotonic chronology;
- at least 45 seconds of admitted local-BLE observation;
- no disqualifying observation-loop gap or observed local-BLE drop;
- no DP/control write.

Share `Nembra-Secure-Link-*-Diagnostics.json` after the test. The artifact is intentionally sanitized and does not contain the private provisioning material.

Only after that gate passes should Nembra generate the smallest stationary DP-mapping experiment. Do **not** repeat the outdoor 17-step ride first.
