# Nembra Capture P0 — secure-link gate

This is the continuation after physical capture `C7D09A22`. **Do not repeat the completed 17-step ride capture.**

## What is already proven

- The scooter is in the Tuya BLE family and exposes service `FD50`.
- The known CoreBluetooth peripheral from the first capture was `6815A5F5-4D1E-E004-BAE8-6DF924123907`.
- FD50 write characteristic `00000001-0000-1001-8001-00805F9B07D0` and notify characteristic `00000002-0000-1001-8001-00805F9B07D0` were observed.
- GATT notification subscription was possible before authentication, but no application characteristic-value frames arrived.
- The first run repeatedly disconnected around 30 seconds because the required Tuya application session was not established.
- No DP mapping, field semantics, telemetry, command acknowledgement, or control authority may be inferred from that capture.

## Current architecture and evidence boundary

CoreBluetooth is used only for the stationary OFF→ON correlation scan. Before authentication begins, Nembra stops that scan and gives authenticated BLE ownership to Tuya's official SmartLife SDK.

Nembra Capture **must not open a second CoreBluetooth connection after Tuya owns the secure session** merely to obtain transport bytes.

The current supported receive surface is `ThingSmartDeviceDelegate` application/DP updates from the official SDK. Those values are SDK-decoded/application-level evidence. Their current `String(describing:)` projections are useful diagnostic evidence but are **not byte-exact, lossless, or raw FD50 transport evidence**.

Raw authenticated FD50/ATT bytes remain a separate unresolved evidence rung. They may be claimed only if a supported same-session capture path is later proven without competing with Tuya's authenticated BLE ownership.

## Current software gates — physical test remains NO-GO until all are accepted

The stationary field attempt may be authorized only after the final composed standalone Capture build proves all applicable gates at one exact head:

1. `ThingSmartHomeKit` is compiled into the standalone `Nembra Capture` target through the provisioned `NembraCapture.xcworkspace`.
2. The matching app-specific `ThingSmartCryption` security component is installed locally and remains outside Git.
3. Private AppKey/AppSecret are supplied only at launch/runtime and are not persisted or exported.
4. The official Tuya SDK itself has an authorized account session; the metadata QR bridge is not treated as SDK login authority.
5. The exact expected scooter device ID is proven to belong to the authorized SDK account/home (owned or shared membership). Login alone is insufficient.
6. The standalone app consumes the canonical authenticated-session authority (`NembraBluetoothCapture`) rather than maintaining an independent boolean/timer acceptance path.
7. The canonical authority is generation-bound, rejects stale/late callbacks, freezes terminal chronology, and cannot resurrect a failed attempt into accepted state.
8. Exact-head standalone Simulator/device build gates are green. Public no-secret CI is compilation/safety evidence only; it cannot prove the privately provisioned SDK path or physical scooter behavior.

Until these are all true, the repository state is **NO-GO** for the physical secure-link experiment.

## Tuya SDK provisioning — non-physical prerequisite

Provision a SmartLife App SDK app on the Tuya Developer Platform for the exact Capture bundle identifier and install the matching iOS security component under the ignored local provisioning path expected by the repo.

Use the repository bootstrap/field installer so the physical candidate is built from `NembraCapture.xcworkspace`, not the bare `.xcodeproj` or the normal Nembra app target.

Keep AppKey/AppSecret, account tokens, verification codes, `local_key`, scooter/session keys, and generated private security material out of Git, logs, screenshots, issues, and Capture exports.

The field utility uses the official SDK's verification-code account flow rather than collecting the Tuya account password. A successful login still does not authorize BLE authentication until exact scooter membership is established through the SDK account/home data.

## Smallest physical test — only after repository status explicitly flips to GO

This test is indoors and stationary. It does **not** repeat the old ride sequence.

1. Keep the scooter **OFF** and start the scooter-OFF baseline.
2. Save the OFF baseline after the instructed observation period.
3. Turn the scooter **ON** and leave it stationary.
4. Scan after power-on and stop the scan/use the best accepted evidence.
5. Capture correlates the likely scooter using accepted evidence such as the known first-capture peripheral, FD50 advertisement evidence, Tuya manufacturer evidence, OFF→ON appearance delta, and proximity. Weak name/RSSI hints do not independently establish identity.
6. The app must confirm that the selected Tuya device is present in the authorized SDK account/home before enabling the secure read-only attempt.
7. Start the secure read-only test. Tuya's SDK becomes the sole authenticated BLE owner. Nembra sends no scooter DP/control command.
8. Keep the scooter stationary and do not interact with it while the gate runs.
9. Acceptance requires one uninterrupted current authenticated generation that remains locally connected for the canonical duration (at least 45 seconds) **and** receives at least one same-generation genuine SDK application/DP update after authentication.
10. Acceptance must come from the canonical preflight verdict. A late callback after failure, a stale callback from another generation, elapsed wall time after a terminal failure, or login without exact scooter membership cannot satisfy the gate.

On pass, the app may state that the **supported Tuya application session** is established and that genuine SDK application data was received. It must not say raw FD50 bytes were captured unless raw transport evidence was independently obtained.

On failure, prepare/share the sanitized diagnostic JSON and stop. The artifact may include correlation evidence, SDK/application update evidence, frozen timing/terminal state, exact build identity, and sanitized failure details. It must explicitly distinguish SDK application values from raw transport bytes and must not export secrets.

## Safety boundary

For this P0 gate Nembra itself sends no lock, unlock, reset, unbind, speed-limit, light, mode, throttle, brake, motor, firmware, or other scooter DP/control command. Any Bluetooth traffic required to establish the supported Tuya session is owned by the official Tuya SDK.

Do not proceed to DP mapping until this gate passes on the final accepted exact build. After it passes, generate the **smallest stationary evidence experiment** from the observed SDK data; do not assume that every visible DP key has known semantics or that a writable property is safe to command.
