# Capture — Tuya SDK scooter-membership authority

Status: REQUIRED before the authenticated stationary ES80 experiment can be called GO.

## Why `ThingSmartUser.isLogin` is not enough

The SmartLife App SDK user session and the user's existing Smart Life / Tuya app account must not be assumed to be the same account/device namespace merely because an email address or phone number matches. A successful SDK login proves only that the SDK session is logged in.

For Nembra's physical gate, the logged-in SDK session must additionally prove that the exact metadata-selected scooter device ID is present in that session's Tuya home/device membership.

Tuya's Home Management contract makes home details the source for device membership. After login:

1. enumerate the SDK account's homes;
2. load each relevant home's details;
3. inspect owned `deviceList` and shared-device membership;
4. require an exact match to Nembra's already-selected Tuya scooter device ID;
5. fail closed if enumeration is incomplete, a required home fails to load, or the exact device is absent.

Do not use device name, product name, RSSI, category, UUID resemblance, or `isLogin` as a substitute for exact cloud device-ID membership.

## Implemented package authority

`TuyaSDKAccountDeviceMembershipGate` now provides the non-secret fail-closed decision boundary.

It rejects:

- empty expected device ID;
- logged-out SDK sessions;
- a logged-in session before home/device enumeration completes;
- a logged-in session containing only some other device;
- incomplete home loading when the scooter was not found.

It accepts only exact owned or shared membership for the expected device ID.

Regression coverage: `TuyaSDKAccountDeviceMembershipGateTests`.

## App integration still required

The current Capture account UI can establish a Tuya SDK login session, but that must NOT by itself authorize `Start secure read-only test`.

Before physical GO, the app must feed real SDK home/device membership into `TuyaSDKAccountDeviceMembershipGate` and make both UI and controller authority consume that verdict. The app should distinguish:

- `SDK logged in` — account session exists;
- `Scooter membership verified` — exact expected device ID is visible to that session;
- `BLE authenticated` — supported local session established;
- `Application data observed` — real `dpsUpdate` data received;
- `Continuity accepted` — authenticated local BLE survived more than 45 seconds.

Only the last four together can advance the ES80 evidence path. Login alone cannot.

## Existing-account transfer / authorization blocker

If a fresh SDK login does not contain the already-bound scooter, do not pair, activate, reset, unbind, or re-home the scooter just to make the test pass.

Use only an official Tuya account/home/device sharing or authorization route that preserves the existing binding. Cross-app QR authorization is documented by Tuya but requires the target SDK app to be allowlisted. Until such an official transfer/authorization route is provisioned and exact scooter membership is visible in the SDK account, the physical experiment remains NO-GO.

## Physical gate after membership is integrated

Stationary only. No old 17-step ride.

Required in one current connection generation:

1. exact scooter membership verified in the official SDK account;
2. supported Tuya BLE connection established by the SDK;
3. Tuya reports local BLE online;
4. at least one genuine non-empty `dpsUpdate` application update is received;
5. authenticated continuity exceeds 45 seconds;
6. no DP command, pairing, activation, reset, unbind, or control action occurs.
