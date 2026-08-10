# Capture — official Tuya SDK provisioning for authenticated read-only preflight

This is the only accepted path from physical capture `C7D09A22` to an authenticated FD50 session. Do not substitute guessed characteristic writes.

## What the user's existing Tuya app account proves

The scooter is already bound and usable in the Tuya app. That establishes account/device ownership context, but Nembra cannot safely copy another iOS app's private session material or treat the Tuya app password as a BLE device key.

The metadata-only Capture flow can also receive the device's cloud `local_key` through the authorized Tuya account/device-sharing API and now retains that value only in this iPhone's Keychain. That is useful private device metadata, but **it is not mechanically accepted as FD50 BLE authentication authority**. Tuya's published Bluetooth pairing/security material distinguishes BLE authentication/pairing inputs from the `local_key` returned by device activation/cloud APIs. Until an official SDK or other documented Tuya route establishes the BLE session, the saved cloud key must not unlock the authenticated physical preflight.

## What Nembra still needs

Tuya's official SmartLife App SDK integration requires an SDK-based app created on the Tuya Developer Platform with a matching iOS Bundle ID plus its own AppKey/AppSecret (and the SDK security component required by the selected SDK generation). Nembra should authenticate the user's Tuya account through that official SDK/account flow and let the SDK establish the documented device session.

The repository must never commit a real AppSecret, user password, access token, device key, session key, nonce, or decrypted credential artifact. Local build-time provisioning should inject non-public app credentials from developer-controlled secret storage. User login should occur through the SDK's supported account flow, not through a custom password capture added to Capture.

## Implemented fail-closed product seam

`NembraBluetoothCapture/TuyaAuthenticatedReadOnlyPreflight.swift` defines the non-secret acceptance gate and a deliberately narrow `TuyaReadOnlyAuthenticationSessionProvider` protocol. It does not expose generic `writeValue`, DP control, unbind, reset, or pairing-reset operations.

`TuyaAuthenticatedReadOnlyPreflightSnapshot` now also carries `TuyaReadOnlyAuthenticationMethod?`. An `.authenticated` state without one of the accepted official method provenances fails closed before payload or duration can unlock anything. The cloud `local_key` is intentionally not an authentication method.

Stationary mapping is unlocked only when one connection generation has:

1. an authenticated Tuya session established by an accepted official route;
2. explicit accepted authentication-method provenance;
3. at least one non-empty application payload; and
4. at least 45 seconds of authenticated connection survival.

Missing SDK/session provisioning, failed authentication, missing provenance, zero payloads, or insufficient survival time remain fail-closed.

## Current external provisioning blocker

The repository can build the fail-closed contract without secrets, but it cannot manufacture the Tuya SmartLife SDK application identity. The remaining external input for route A is a Tuya Developer Platform SmartLife App SDK configuration whose iOS Bundle ID matches the Capture app, together with the SDK package/security component and privately supplied AppKey/AppSecret required by that Tuya SDK generation.

Do not put those secrets in Git, issue bodies, pull requests, exported Capture JSON, or chat transcripts. Once the SDK package is available to the private Xcode build, the integration adapter should consume secrets from private build/runtime provisioning and expose only non-secret session milestones to Nembra.

## Next integration step

Provision the official Tuya iOS SDK for Nembra's Bundle ID, inject its app credentials privately, authenticate the user's own Tuya account through the SDK, and adapt only the resulting authenticated read/notification session into `TuyaReadOnlyAuthenticationSessionProvider`.

The first adapter must be intentionally narrow:
- match the already-bound scooter, not activate/pair/reset it;
- establish the supported BLE session;
- receive/decrypt application notifications through the supported Tuya stack;
- expose non-secret authentication/currentness milestones plus raw application payload receipts needed for offline analysis;
- expose no generic DP write/control API.

Do not start another outdoor ride to test this. The first accepted physical run is stationary and needs accepted official authentication provenance, one real application payload, and at least 45 seconds of authenticated connection continuity.
