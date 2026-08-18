# Nembra Capture P0 — secure-link gate

PROCEDURE_ID: `ES80-AUTHENTICATED-STATIONARY-v1`

This is the continuation after physical capture `C7D09A22`. **Do not repeat the completed 17-step ride capture.**

## What is already proven

- The scooter is in the Tuya BLE family and exposes service `FD50`.
- Capture `C7D09A22` observed CoreBluetooth peripheral `6815A5F5-4D1E-E004-BAE8-6DF924123907` for that capture only.
- FD50 write characteristic `00000001-0000-1001-8001-00805F9B07D0` and notify characteristic `00000002-0000-1001-8001-00805F9B07D0` were observed as transport facts.
- GATT notification subscription was possible before authentication, but no application characteristic-value frames arrived.
- The first run repeatedly disconnected around 30 seconds because the required Tuya application session was not established.
- No DP mapping, field semantics, telemetry, command acknowledgement, stable device identity, or control authority may be inferred from that capture.

The historical CoreBluetooth UUID is **descriptive capture-local evidence only**. It must not authorize the current attempt and must not be used to break a correlation tie.

## Current architecture and evidence boundary

Current target authority is earned only by one package-owned, fresh-manager `OFF1 → ON1 → OFF2 → ON2` correlation series using full CoreBluetooth peripheral identity and the accepted bounded observation-window contract.

Each of the four windows must mechanically reach scan readiness and the accepted receipt-bounded minimum duration before it can be sealed. The app may guide with a timer, but elapsed UI time is not evidence. Name, RSSI, FD50 presence, Tuya manufacturer/product hints, service-name similarity, and the historical C7D09A22 UUID are descriptive only and cannot mint target authority.

The package must end the four-window series with exactly one repeatable full UUID. No repeatable candidate or more than one repeatable candidate is a terminal **STOP / restart from OFF1** result. There is no hint-based override.

A unique package result is still not enough to begin authentication. The operator must explicitly confirm the freshly correlated Bluetooth target for this attempt. That confirmation is current-session authority only and does not establish permanent scooter identity.

After confirmation and a fresh same-account exact-device membership recheck, authenticated BLE ownership belongs only to Tuya's official SmartLife SDK. Nembra must not open a second independent CoreBluetooth connection to obtain transport bytes.

The current supported receive surface is `ThingSmartDeviceDelegate` application/DP updates from the official SDK. Those values are SDK-decoded/application-level evidence. Their current `String(describing:)` projections are useful diagnostic evidence but are **not byte-exact, lossless, or raw FD50 transport evidence**.

Raw authenticated FD50/ATT bytes remain a separate unresolved evidence rung. They may be claimed only if a supported same-session capture path is later proven without competing with Tuya's authenticated BLE ownership.

## Current software gates — physical test remains NO-GO until all are accepted

The stationary field attempt may be authorized only after the final composed standalone Capture build proves all applicable gates at one exact head:

1. `ThingSmartHomeKit` is compiled into the standalone `Nembra Capture` target through the provisioned `NembraCapture.xcworkspace`.
2. The matching app-specific `ThingSmartCryption` security component is installed locally and remains outside Git.
3. The public SmartLife dependencies are exactly pinned/resolved to the reviewed `ThingSmartHomeKit 7.8.0` and `ThingSmartBusinessExtensionKit 7.8.0` inputs, with the resolved `Podfile.lock` preserved and fingerprinted by the repository bootstrap.
4. Private AppKey/AppSecret are provisioned only through the reviewed ignored local `NembraTuyaPrivateConfig` path. They are not committed, passed in process arguments, placed in the `devicectl` launch environment, logged, screenshot, or exported.
5. The official Tuya SDK itself has an authenticated session for the **same account method that owns the scooter**. For an Apple-backed Smart Life account, use Sign in with Apple through Tuya's documented Apple OAuth transport; for an email/phone account, the verification-code path remains available. Metadata QR approval alone is not SDK login authority, and a different Tuya account must never be substituted merely because it can log in.
6. The exact expected scooter device ID is proven to belong to that same current SDK account/home (owned or shared membership). Login alone is insufficient, and the membership proof is leased to the exact current account UID.
7. OFF1 discovery cannot begin until compiled field-build provenance and the same-current-account exact-device authority are current.
8. Current target authority comes only from the package-owned fresh `OFF1 → ON1 → OFF2 → ON2` result, followed by explicit operator confirmation. Historical UUID/name/RSSI/FD50/Tuya hints remain non-authoritative.
9. The standalone app consumes the canonical authenticated-session authority (`NembraBluetoothCapture`) rather than maintaining an independent boolean/timer acceptance path.
10. The canonical authority is generation-bound, rejects stale/late callbacks, freezes terminal chronology, retires hidden generations before retry, and cannot resurrect a failed attempt into accepted state.
11. Package-already-terminal observation-continuity failures are mirrored into app ownership exactly once; the app does not attempt a second ledger terminal or invent a disconnect/source-loss fact.
12. Exact-head standalone Xcode 27 / iPhone-12-class Simulator gates are terminal green on the unchanged final candidate. Public no-secret CI is software evidence only; it cannot prove the privately provisioned SDK path or physical scooter behavior.
13. The privately provisioned workspace builds/signs/installs the exact accepted source on the intended iPhone 12 / iOS 27, with exact build identity visible in the app and retained in exported evidence. For an Apple-backed account, the signed app must also have a valid Sign in with Apple entitlement/provisioning path and the Tuya developer workspace must have the corresponding Apple third-party-login capability configured; otherwise **STOP** before Bluetooth correlation.

Until all applicable software/private-device prerequisites are true and the repository explicitly records `GO`, the physical secure-link experiment is **NO-GO**.

## Tuya SDK provisioning — non-physical prerequisite

Provision a SmartLife App SDK app on the Tuya Developer Platform for the exact Capture bundle identifier and install the matching iOS security component under the ignored local provisioning path expected by the repo.

Use the repository provisioning/bootstrap/field installer so the physical candidate is built from `NembraCapture.xcworkspace`, not the bare `.xcodeproj` or the normal Nembra app target. Preserve the accepted `Podfile.lock`; do not run an ad-hoc `pod update` before a physical evidence run.

Keep AppKey/AppSecret, account tokens, Apple identity tokens, verification codes, `local_key`, scooter/session keys, and generated private security material out of Git, logs, screenshots, issues, chat, and Capture exports.

The field utility uses the official SDK account transport that corresponds to the same Smart Life account that owns the scooter: Sign in with Apple for an Apple-backed account, or Tuya email/phone verification code when that is the account's real login method. A successful account login still does not authorize any Bluetooth correlation or authentication until exact scooter membership is established and bound to the same current SDK account.

## Smallest physical test — only after repository status explicitly flips to GO

This test is indoors and stationary. It does **not** repeat the old ride sequence. Do not touch the phone while moving; this experiment requires no riding or scooter motion at all.

### Preflight

1. Connect/unlock the intended iPhone 12, install the exact accepted signed Capture build, verify the app shows authoritative compiled field-build provenance, and verify `Procedure` is exactly `ES80-AUTHENTICATED-STATIONARY-v1`.
2. Keep the scooter stationary and initially **OFF**.
3. In Capture, use the same official Tuya SDK account method that owns the scooter. For this Apple-backed Smart Life account, use **Sign in with Apple**. Use email/phone verification code only when that is genuinely the owning account's login method. If the required account method is unavailable or the SDK does not enter the expected account, **STOP**; do not fall back to a different account.
4. Require the app to freshly verify the exact expected scooter device ID in the current SDK account/home and retain the same-account UID lease.
5. If build authority, SDK login, exact membership, or account identity changes at any point, **STOP**. Do not begin or continue Bluetooth correlation.

### Fresh four-window target correlation

6. Start **OFF1** with the scooter OFF. Wait until Capture says the fresh manager scan is live. Keep the scooter state unchanged until the package has earned the accepted receipt-bounded minimum duration, then seal OFF1.
7. Turn the scooter **ON**, let the physical state settle, then start **ON1**. Wait for scan liveness and the accepted minimum duration, then seal ON1.
8. Turn the scooter **OFF**, let it settle, then start **OFF2**. Wait for scan liveness and the accepted minimum duration, then seal OFF2.
9. Turn the scooter **ON**, let it settle, then start **ON2**. Wait for scan liveness and the accepted minimum duration, then seal ON2.
10. The package must report exactly one repeatable full CoreBluetooth UUID across the accepted four-window chronology. If it reports none, ambiguity, invalid authority, invalid window order, scan-readiness failure, or chronology failure, **STOP** and restart only from a fresh OFF1 after correcting the stated blocker.
11. Read the result as **correlated Bluetooth target for this attempt**, not verified permanent ES80 identity. Do not use the historical C7D09A22 UUID, FD50, Tuya manufacturer data, name, or RSSI to override the package result.
12. Explicitly tap **Confirm correlated Bluetooth target**. If the app no longer has the same current SDK account/device authority, confirmation must fail closed and the attempt must restart.

### Supported read-only Tuya session

13. Start the secure read-only test only after the app has re-proven current same-account exact-device authority. Tuya's SDK becomes the sole authenticated BLE owner. Nembra sends no scooter DP query/control command and opens no second CoreBluetooth connection.
14. After the SDK transport-success callback, allow only the accepted bounded local-BLE settlement window. Authenticated chronology begins only after Tuya current local-BLE status is actually observed online. Timeout or monotonic-clock regression is a terminal **STOP**, not account-source drift and not a fabricated disconnect.
15. Keep the scooter stationary, keep Capture in the foreground, and do not change mode/light/brake/throttle/charger state during this preflight.
16. Acceptance requires one uninterrupted current generation with all of the following: supported SmartLife SDK authentication provenance, current same-account exact-device authority, Tuya local BLE observably online, no disqualifying continuity/clock gap, at least one genuine non-empty same-generation `ThingSmartDeviceDelegate.dpsUpdate`, and at least 45 seconds of canonical authenticated observation.
17. The app must seal the canonical ready prefix before presenting success. Delayed callbacks after seal or failure cannot mutate the accepted artifact.
18. Prepare/share the sanitized diagnostic JSON. The artifact must carry exact build/source provenance plus correlation provenance and must explicitly retain `rawFD50BytesCaptured=false`, `dpQueriesSent=false`, and `dpCommandsSent=false` for this supported structured-SDK path.

### Stop conditions

Stop the attempt and preserve only already-legitimate evidence if any of these occurs:

- field-build provenance becomes non-authoritative;
- SDK account logout/switch or exact-device membership/UID lease changes;
- a four-window scan never proves liveness or cannot earn its minimum receipt-bounded duration;
- correlation is none/ambiguous or its chronology/provenance is rejected;
- explicit target confirmation is unavailable;
- local-BLE settlement times out or its monotonic clock regresses;
- authenticated observation has a disqualifying gap/clock regression;
- Tuya local BLE is actually observed offline;
- authenticated application evidence does not arrive before the accepted deadline;
- any package/app lifecycle terminal cannot prove exact-generation retirement;
- any secret appears in UI/log/export;
- any Nembra DP query/publish, scooter control, unbind/reset/OTA, or second post-auth CoreBluetooth ownership path is observed.

On failure, share the sanitized diagnostic JSON if available and stop. **Do not compensate by repeating the old outdoor ride or by guessing packets/DPs.**

## Safety boundary

For this P0 gate Nembra itself sends no lock, unlock, reset, unbind, speed-limit, light, mode, throttle, brake, motor, firmware, DP query, or other scooter control command. Any Bluetooth traffic required to establish/maintain the supported Tuya session is owned by the official Tuya SDK.

Passing this gate establishes only a supported authenticated Tuya application session plus genuine same-generation structured SDK application evidence. It does not establish raw FD50 bytes, permanent CoreBluetooth identity, DP meanings, speed/battery/power semantics, command acknowledgement, or safe write authority.

After PASS, generate the **smallest stationary evidence experiment** from the observed SDK data. Do not assume every visible DP key has known semantics or that a writable property is safe to command. Movement/GPS calibration remains later.