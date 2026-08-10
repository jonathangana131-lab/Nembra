# Capture — official Tuya SDK provisioning for authenticated read-only preflight

This is the only accepted path from physical capture `C7D09A22` to an authenticated FD50 session. Do not substitute guessed characteristic writes.

## What the user's existing Tuya app account proves

The scooter is already bound and usable in the Tuya app. That establishes account/device ownership context, but Nembra cannot safely copy another iOS app's private session material or treat the Tuya app password as a BLE device key.

## What Nembra still needs

Tuya's official SmartLife App SDK integration requires an SDK-based app created on the Tuya Developer Platform with a matching iOS Bundle ID plus its own AppKey/AppSecret (and the SDK security component required by the selected SDK generation). Nembra should authenticate the user's Tuya account through that official SDK/account flow and let the SDK establish the documented device session.

The repository must never commit a real AppSecret, user password, access token, device key, session key, nonce, or decrypted credential artifact. Local build-time provisioning should inject non-public app credentials from developer-controlled secret storage. User login should occur through the SDK's supported account flow, not through a custom password capture added to Capture.

## Implemented fail-closed product seam

`NembraBluetoothCapture/TuyaAuthenticatedReadOnlyPreflight.swift` now defines the non-secret acceptance gate and a deliberately narrow `TuyaReadOnlyAuthenticationSessionProvider` protocol. It does not expose generic `writeValue`, DP control, unbind, reset, or pairing-reset operations.

Stationary mapping is unlocked only when one connection generation has:

1. an authenticated Tuya session;
2. at least one non-empty application payload; and
3. at least 45 seconds of authenticated connection survival.

Missing credentials, failed authentication, zero payloads, or insufficient survival time remain fail-closed.

## Next integration step

Provision the official Tuya iOS SDK for Nembra's Bundle ID, inject its app credentials privately, authenticate the user's own Tuya account through the SDK, and adapt only the resulting authenticated read/notification session into `TuyaReadOnlyAuthenticationSessionProvider`.

Do not start another outdoor ride to test this. The first accepted physical run is stationary and needs only one real payload plus >45 seconds of authenticated connection continuity.
