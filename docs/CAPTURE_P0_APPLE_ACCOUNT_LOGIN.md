# Capture P0 — Apple-account Tuya login

STATUS: SOFTWARE PATH REQUIRED / PRIVATE PLATFORM CONFIGURATION + PHYSICAL MEMBERSHIP STILL UNPROVEN

The intended scooter account uses Apple-backed Smart Life sign-in, so Capture must not assume email/phone verification can enter the same Tuya account.

Nembra field contract:
- Apple authorization is owned by AuthenticationServices / Sign in with Apple.
- The transient Apple identity token stays in memory and is handed directly to Tuya's official `loginByAuth2` Apple (`ap`) account transport.
- Any Tuya OAuth failure string is scrubbed against the exact submitted identity token, Apple user identifier and optional email before presentation.
- The identity token is never persisted, exported, logged, or converted into Capture evidence.
- OAuth success is account transport only. Capture re-reads the official SDK login state and still requires fresh exact scooter membership plus the current-account UID lease before Bluetooth discovery.
- Email/phone verification remains an alternate account path.
- Private Tuya third-party-login configuration and signed Apple capability provisioning remain field prerequisites and are not proven by public source.

Official Tuya iOS documentation: https://developer.tuya.com/en/docs/app-development/iOS-user-thirdparty?id=Kaixu9bbogqxi

PHYSICAL STATUS: NO-GO until the final composed exact build passes software, private provisioning, runtime, membership, and stationary field gates.
