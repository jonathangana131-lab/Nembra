# ES80 Research Capture App Wiring — V14

## Status

This document describes the dependency-bound Nembra Capture app shell recovered onto the live V14 foreground controller lineage.

- Feature: **Nembra Capture / ES80 physical truth**
- Shell branch base: controller PR #487 exact product `291b9ffe6e99ed6f414940a6b0fb8c49f01a3768`
- Launch surface: shared `Nembra ES80 Research` scheme or DEBUG `--es80-passive-capture`
- Application BLE writes: **none added**
- Physical Experiment One: **DO NOT RUN / NO-GO** until the final composed exact-head gate accepts controller, recovery, correlation, recipe/provenance, app shell, visual/accessibility/performance evidence, and runbook requirements.

This shell is app-visible product integration. It does not by itself authenticate an AOVOPRO ES80, prove RF completeness, decode GATT/Tuya/DP semantics, establish battery/voltage/current/power/speed meaning, or authorize commands.

## Launch isolation

Normal `NembraApp` startup remains the production application runtime.

The research shell is reachable only in DEBUG through either:

- launch argument `--es80-passive-capture`; or
- environment variable `NEMBRA_ES80_PASSIVE_CAPTURE=1`.

The dedicated shared scheme selects the research launch path. The shell does not expose normal vehicle controls or the older advanced package console.

## Product authority boundary

`ES80CaptureShellView` owns presentation, explicit candidate selection, foreground lifecycle policy, a conservative presentation wait, file sharing, and user-facing failure text.

It does **not** own evidence chronology.

The live `ForegroundCoreBluetoothCaptureController` remains authoritative for:

1. explicit target-scoped durable session creation;
2. finite passive CoreBluetooth acquisition;
3. canonical artifact authority;
4. typed Ready admission and recorder mutation;
5. exact Ready queue commit;
6. exact Horizon admission from the committed Ready epoch;
7. exact queue cutoff and FIFO drain;
8. Horizon recorder mutation and typed queue commit;
9. immutable JSON encoding/freeze;
10. post-H evidence retirement and transport isolation.

The shell must never substitute a UI state, local timer, candidate name, RSSI, or UUID for those authorities.

## Capture flow

### 1. Stationary preflight

The UI keeps the passive-only and foreground-only boundary visible before scanning. Bluetooth must be powered on. Candidate discovery is not identity proof.

### 2. Explicit scan and candidate selection

`startScanning(captureAdvertisementCadence: false)` opens the broad candidate catalog. The operator explicitly chooses a currently present, connectable candidate after following the accepted physical-correlation procedure.

Names, RSSI, services, short IDs, and full CoreBluetooth UUIDs remain candidate/correlation evidence only.

### 3. Open one target session

`connect(to:)` creates or continues the controller-owned selected-target durable session. The app shell does not create a parallel recorder or evidence model.

### 4. Finite passive acquisition

While discovery/read/subscription setup is incomplete, the UI stays in preparation. The screen remains awake and the application must stay active in the foreground.

### 5. Durable Ready

The shell does not call a public "mark ready" API. It waits until `controller.canFinalizeObservationHorizon` becomes true. That property is exposed only after the controller's package-owned Ready transaction has durably crossed the recorder and committed its typed queue state under the current artifact authority.

### 6. Conservative 60-second presentation wait

When the shell first observes the controller's durable Ready eligibility, it starts a local monotonic 60-second wait using `DispatchTime.uptimeNanoseconds`.

This wait is deliberately **presentation policy, not evidence**:

- it starts no earlier than the real durable Ready state;
- it cannot mint, rewrite, or attest the package Ready timestamp;
- it cannot prove continuity or RF completeness;
- final Experiment One assessment must still consume the immutable artifact's package-owned Ready/Horizon chronology.

The shell therefore cannot make a too-early Finish action available merely because finite GATT acquisition completed.

### 7. Canonical Horizon finalization

Finish Capture requires both:

- current `controller.canFinalizeObservationHorizon == true`; and
- completion of the conservative local presentation wait.

The shell then calls only:

`encodedFinalizedObservationHorizonJSON(prettyPrinted: true)`

That controller operation owns the exact accepted Horizon cutoff, drains the admitted FIFO prefix, records Horizon, commits the typed queue state without an intervening MainActor suspension, encodes the immutable JSON, validates authority, freezes the artifact, and retires only proven post-H evidence.

The shell intentionally does **not** use plain `encodedCaptureJSON()` as the Experiment One completion path.

### 8. Post-finalization transport teardown

Only after canonical Horizon JSON succeeds does the shell call:

`teardownActiveConnectionAfterFinalization()`

This keeps ordinary operator cancellation semantics out of a successfully finalized artifact and uses the controller's post-H transport-isolation contract.

### 9. Immutable export

The exact returned bytes are decoded only to show descriptive counts and then wrapped for the system JSON file exporter. The exported data are not regenerated from UI state.

The UI's `Receipt timeline span` remains descriptive first-to-last receipt time and may include explicit continuity gaps. It is not the authoritative Ready-to-Horizon duration.

## Foreground failure

If the app leaves `.active` while a target session exists and before the immutable Horizon artifact has been sealed, the shell fails closed and calls:

`invalidateActiveCaptureForForegroundLoss()`

The session is then presented as non-exportable. It is not mislabeled as an operator cancel and it is not silently resumed after background delivery uncertainty.

## Disconnect-before-H behavior

If the selected-target transport reaches idle before canonical Horizon finalization, the shell does not offer ordinary snapshot export. It fails closed and instructs the operator to relaunch and repeat the capture.

This is intentionally stricter than the stale V13 shell, which could retain/export a disconnected pre-H snapshot.

## Accessibility and visual behavior

The research shell keeps:

- one obvious primary action per state;
- 54-point primary and 48-point secondary action heights;
- readable high-contrast dark presentation;
- combined candidate accessibility labels including the short candidate identifier without calling it identity proof;
- Reduce Motion-aware candidate-list animation;
- foreground/passive safety text available to VoiceOver;
- a dedicated accessibility identifier `es80.capture-shell`.

The UI test captures the launch surface and mechanically rejects premature Finish, normal vehicle controls, and the legacy advanced console.

## Current dependency blockers

This app shell is **not final physical GO authority**. At minimum, final product composition still has to reconcile and accept the live V14 dependency stack, including:

- #487 controller / canonical Ready-Horizon authority;
- pre-H and recorded-H recovery/resolution lineage;
- corrected passive continuity and current physical-correlation composition;
- `ES80-FINGERPRINT-v1` recipe integration;
- exact build identity/provenance embedded into the final artifact/run package rather than merely operator-declared;
- exact final-head Xcode 27 build/tests;
- iPhone 12 / iOS 27 app-visible screenshots and accessibility review;
- performance and no-fake-telemetry checks;
- V14 physical runbook gate.

Green ancestor/package checks do not bless this moved composition. A Simulator screenshot is not physical scooter evidence.

## Physical truth boundary

Until those blockers are closed, this shell proves only that the current app has an intentional, passive, foreground-only UI path toward the controller's canonical Ready/Horizon artifact lifecycle.

**PHYSICAL AOVOPRO ES80 EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.**
