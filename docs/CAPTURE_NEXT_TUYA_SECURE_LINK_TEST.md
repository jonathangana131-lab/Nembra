# Nembra Capture — next physical test after C7D09A22

## What C7D09A22 closed

The first real physical artifact identified the scooter transport as Tuya BLE over service `FD50`, with the prior physical CoreBluetooth peripheral ID `6815A5F5-4D1E-E004-BAE8-6DF924123907` and advertising local name `demo`. The 17-step run completed but received zero application characteristic payloads. The connection repeatedly dropped at the unauthenticated timeout window, so repeating that ride sequence before supported Tuya authentication would waste another field run.

## Current physical status

**NO-GO. Do not repeat the old 17-step calibration yet.**

The next physical action remains one short indoor/stationary secure-link experiment, but only after the exact current field build passes all software/private-provisioning/account/device-authority gates described below.

## The stationary experiment

When the exact field build is authorized, it does only this:

1. Establish the official SmartLife SDK app identity and current SDK account session.
2. Prove the metadata-selected scooter is actually present in the current SDK account/home device inventory.
3. Only then, with the scooter OFF, collect a short local Bluetooth correlation baseline.
4. Turn the scooter ON and identify it only through accepted target authority: the prior exact CoreBluetooth UUID or corroborating `FD50 + Tuya company 0x07D0`. Name, RSSI, score and power-cycle hints may rank candidates but do not authorize identity.
5. Stop Nembra's CoreBluetooth scan before secure authentication starts.
6. Let the official Tuya SmartLife App SDK exclusively own the authenticated BLE connection.
7. Attach the accepted SDK application-update observer. Do not publish/query DPs.
8. Use the canonical authenticated-session ledger/preflight to track same-generation local-BLE continuity and admitted application updates.
9. PASS only when the canonical verdict is ready: local BLE is currently online, accepted authenticated observation is **at least 45 seconds**, at least one genuine non-empty application update belongs to the same authentication generation, and the read-only command/control boundary remains intact.
10. Export sanitized diagnostics.

## Safety boundary

This experiment must not:

- turn `local_key` into a guessed BLE session key;
- construct/fuzz raw FD50 authentication frames;
- open a second CoreBluetooth connection after Tuya owns BLE;
- publish or query a DP;
- change lock, speed limit, mode, light, cruise, throttle, brake, firmware, or any scooter setting;
- unbind/remove/reset/factory-reset the scooter;
- assign battery, speed, mode, brake, throttle, light, power, current, voltage, odometer or other semantics to any DP yet.

Opaque SDK application/DP IDs and values may be recorded only as evidence for a later mapping pass. They are application-level SDK evidence, not raw FD50 characteristic bytes.

## Official Tuya integration gate

The supported iOS path requires Tuya's SmartLife App SDK and the app-specific security material generated for a Tuya Developer Platform iOS app whose Bundle ID matches the Capture target. The generated security component and AppKey/AppSecret remain private and must never be committed to this repository.

The physical secure-link control remains unavailable unless the exact field app has all required authority, including:

- `ThingSmartHomeKit` and the matching app-specific security component in the signed local field build;
- privately supplied `NEMBRA_TUYA_APP_KEY` and `NEMBRA_TUYA_APP_SECRET` for the Xcode Run session;
- a current official SDK account session;
- exact metadata-selected scooter membership proven from the SDK account/home device source;
- accepted deterministic local target correlation;
- current same-generation SDK-owned local BLE/session evidence;
- canonical read-only preflight readiness.

The metadata QR session is intentionally not treated as an SDK BLE-authentication session.

## Private Xcode launch handoff

Do not pass AppKey/AppSecret through `devicectl` arguments. That rejected path is removed.

The supported private local development handoff is:

1. run `scripts/field/install_one_time_capture.command` on the clean exact flagship branch to validate private SDK provisioning, signing and the intended connected iPhone;
2. in the generated/open `NembraCapture.xcworkspace`, duplicate `Nembra Capture` to a **personal / not-shared** field scheme;
3. in **Edit Scheme > Run > Arguments > Environment Variables**, enter enabled `NEMBRA_TUYA_APP_KEY` and `NEMBRA_TUYA_APP_SECRET` only inside Xcode;
4. Run that personal scheme on the intended iPhone;
5. immediately after the stationary experiment, remove/disable both values and delete the personal field scheme.

Do not paste those values into Terminal, shell history, Git, issue/PR text, console logs, or Capture diagnostics. The personal scheme itself is only a private provisioning carrier; it does not grant physical GO.

## Remaining product blockers before the experiment can run

The final exact app must mechanically fail closed **before the first scooter-OFF scan** unless the current SDK account and exact scooter-membership authority are still valid. It must also redact submitted account identifiers and other private values from SDK error text before that text reaches UI/logging.

Expected-red source contracts currently pin those boundaries. Until the product implementation satisfies them on the final exact head and required QA passes, stop before scanning the scooter.

## Why one BLE owner matters

An earlier scaffold authenticated through the official SDK and then attempted to attach a separate CoreBluetooth connection to read FD50 notifications. That architecture is rejected. Tuya's SDK connection plus its application-update callbacks form the sole authenticated observation path for this preflight.

## Acceptance artifact

Share `Nembra-Secure-Link-*-Diagnostics.json` only after the canonical test finishes. It may include deterministic target evidence, gate states, accepted monotonic continuity, SDK-local status, application-update chronology, sanitized opaque values and failures. It must exclude AppSecret, account verification codes/tokens, passwords and `local_key`.

If this secure-link test later passes physically, the next experiment is the smallest stationary DP-correlation sequence needed by the evidence—not an automatic replay of the old ride. Movement/GPS work remains blocked until stationary application data is visible and repeatable.
