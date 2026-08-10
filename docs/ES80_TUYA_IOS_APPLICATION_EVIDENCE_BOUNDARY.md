# ES80 Tuya iOS application-evidence boundary

Research checkpoint: **2026-08-10**

Feature: **Nembra Capture / ES80 authenticated stationary physical truth**

Status: **PUBLIC-SURFACE RESEARCH / NOT PHYSICAL PROOF / PHYSICAL NO-GO**

This checkpoint narrows one specific V14 question: what evidence authority is actually documented at the current Tuya SmartLife iOS application boundary used by Nembra Capture?

It does **not** establish the private ES80 DP schema, raw FD50 notification contents, telemetry semantics, or a physical-session PASS. It also does not prove that undocumented/private SDK headers cannot expose lower-level bytes. The final accepted build and physical artifact remain authoritative.

## Current documented SmartLife device callback

Tuya's current iOS Smart App SDK device-management documentation shows `ThingSmartDeviceDelegate` delivering device state changes through:

```swift
func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable : Any]?)
```

The same documentation describes `ThingSmartDeviceModel.dps` and `dpCodes` as dictionaries of device data points. Its example for querying a DP says the response is returned through the same `dpsUpdate` delegate callback.

Official source reviewed 2026-08-10:

- Tuya Developer — Device Management (iOS): https://developer.tuya.com/en/docs/app-development/ios-saas-commercial-lighting-device-manager?id=Kampuheit31oz

### Authority implication

A value received through this documented callback is **structured SDK application evidence**.

It may legitimately prove, after Nembra's current-generation/source/chronology gates admit it, that a non-empty application update was received from the supported SmartLife session.

It does **not** by itself prove:

- byte-exact FD50 notification bytes;
- exact GATT characteristic bytes;
- DP transport framing;
- encryption/framing internals;
- speed, battery, voltage, current, power, mode, odometer, command acknowledgement, or any other field meaning.

`String(describing:)` of a DP dictionary/value is a presentation/serialization of the SDK object. It is not a lossless claim about the bytes that existed on the BLE characteristic.

## Current documented iOS Bluetooth-manager surface

Tuya's current iOS Bluetooth Technology Stack documentation describes the public Smart App SDK Bluetooth manager surface for Bluetooth discovery, pairing/activation, connection state, device control, and related lifecycle behavior.

Official source reviewed 2026-08-10:

- Tuya Developer — Bluetooth Technology Stack (iOS): https://developer.tuya.com/en/docs/app-development/ios-saas-commercial-lighting-ble?id=Kamptfelkvdwl

The public documentation reviewed for this checkpoint did **not reveal a documented byte-exact characteristic-notification callback** equivalent to CoreBluetooth's raw `Data` value update for the already-authenticated SmartLife-owned session.

That statement is deliberately narrow:

- it is a finding about the **public documentation reviewed**;
- it is **not proof of impossibility**;
- it does not exclude private headers, product-specific extensions, a different accepted SDK API, or another legitimate one-owner evidence source;
- Nembra must inspect the exact reviewed private field dependency before declaring the raw-byte path unavailable.

## V14 one-owner consequence

Nembra's current stationary gate requires fresh CoreBluetooth target correlation to retire before the supported Tuya SDK takes authenticated BLE ownership. Nembra must not reopen a competing CoreBluetooth connection merely to obtain raw bytes.

Therefore the evidence ladder is:

1. fresh package-owned OFF1 -> ON1 -> OFF2 -> ON2 target correlation;
2. explicit operator confirmation;
3. exact current Tuya account/device source authority;
4. supported Tuya authenticated BLE ownership;
5. same-generation structured `dpsUpdate` evidence, if observed;
6. byte-exact FD50 evidence **only if** a separately accepted legitimate one-owner source exists;
7. telemetry semantics only after later repeatable physical decoding/correlation evidence.

Structured application evidence is useful and may close the first authenticated-application-session question. It cannot silently satisfy a stronger raw-byte requirement.

## Required decision if raw FD50 remains unavailable

If inspection of the exact private field SDK plus a legitimate stationary runtime demonstrates that the supported one-owner session exposes structured application updates but no accepted byte-exact FD50 source, the swarm must not fabricate raw evidence and must not create a second BLE owner.

Instead, a reviewed successor to the physical gate must explicitly choose between:

- retaining the raw-FD50 requirement and identifying a legitimate source that satisfies the one-owner contract; or
- deliberately splitting the experiment so the next accepted physical milestone is **authenticated structured application evidence + >=45 s canonical continuity**, while raw-byte acquisition remains a separate unresolved research rung.

That would be a deliberate contract revision, not an implementation shortcut. Until such a revision is reviewed and composed, the existing stronger gate remains in force.

## Relation to current code

The current Capture app's `SmartLifeDriver` receives `ThingSmartDeviceDelegate.dpsUpdate`, projects DP keys/values into strings, and feeds only the non-empty application-update fact into `TuyaAuthenticatedReadOnlySessionLedger`. Its export labels the representation as application-level SDK data and records `rawFD50BytesCaptured = false`.

That is the correct authority level for the documented callback. It must stay that way unless later evidence legitimately raises the boundary.

## Relation to C7D09A22

Accepted physical capture `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E` established current Tuya/FD50 **transport behavior only**. It did not contain application characteristic payload evidence and did not establish telemetry semantics.

This public-SDK research does not upgrade that capture. It only clarifies what the next authenticated field artifact may truthfully claim if the documented SmartLife callback fires.

## Physical status

**NO-GO / DO NOT SCAN / DO NOT RUN.**

Software convergence, exact-head Xcode/runtime acceptance, private intended-device build provenance, and the final reviewed stationary procedure are still required before the next ES80 physical action.
