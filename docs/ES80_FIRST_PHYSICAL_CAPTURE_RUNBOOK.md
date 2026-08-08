# ES80 First Physical Capture Runbook

Status: **NO-GO — PREPARED TEMPLATE ONLY**

Purpose: collect the first trustworthy stationary, charger-disconnected, passive/read-only AOVOPRO ES80 artifact for recipe `ES80-FINGERPRINT-v1`.

This runbook does **not** authorize a field run until the approval block below is fully populated from one terminally accepted exact source head and one independently verified signed installable for the intended iPhone. Blank, pending, cancelled, skipped, ancestor, Simulator-only, or mismatched evidence means **NO-GO**.

## 1. Approval block — must be complete before GO

- Decision: **NO-GO**
- Accepted source SHA: `UNFILLED`
- Terminal Xcode 27 exact-head workflow/run: `UNFILLED`
- Xcode conclusion: `UNFILLED — must be SUCCESS`
- Recipe: `ES80-FINGERPRINT-v1`
- Procedure version: `UNFILLED`
- Human-readable Capture build identifier: `UNFILLED`
- Build-instance UUID: `UNFILLED`
- Signed installable kind/path reference: `UNFILLED`
- Signed installable SHA-256: `UNFILLED`
- Running executable SHA-256: `UNFILLED`
- Raw Info.plist SHA-256: `UNFILLED`
- Code-signing verification: `UNFILLED`
- Intended-device provisioning verification: `UNFILLED`
- Intended device/baseline: `iPhone 12 / iOS 27`
- Exact build installed on intended device: `UNFILLED`
- Retained pre-field screenshots/artifacts inspected: `UNFILLED`
- Approver/freeze checkpoint: `UNFILLED`

**Do not change Decision to GO unless every required item above is concrete and mutually consistent.** The installed app must be the exact signed research build produced from the accepted source SHA; the recipe/build identity embedded in the signed app must match the independently retained evidence.

## 2. Non-negotiable safety and truth boundary

- Scooter remains **stationary** for the entire first experiment.
- Charger remains **disconnected** for the entire capture.
- This is a **passive/read-only** experiment.
- Do not ride during this procedure.
- Do not perform or approve any application characteristic-value write or vehicle command.
- Do not treat a Bluetooth name, RSSI, service-name hint, short identifier, or a single appearance as verified ES80 identity.
- Do not claim GATT, Tuya/DP, battery, voltage, current, power, speed, command acknowledgement, or other protocol meaning from this run unless later analysis actually earns that claim.
- Simulator/software evidence is not physical ES80 evidence.

## 3. Before opening Capture

1. Place the scooter where it can remain stationary and safely be powered off/on without riding it.
2. Disconnect the charger and keep it disconnected.
3. Keep the iPhone with the scooter; do not begin if the phone/build identity does not match the Approval block.
4. Confirm the intended signed research build is installed and launches.
5. Confirm Bluetooth permission/state and app foreground operation are usable.
6. If any build, signing, provisioning, recipe, or identity field disagrees with the Approval block, stop: **NO-GO**.

## 4. Stationary preflight

1. Launch the dedicated Capture research build.
2. Confirm the app enters Nembra Capture rather than ordinary app mode.
3. In stationary preflight, declare the real charger state as **Disconnected**.
4. Do not continue if the charger is connected or its state is uncertain.
5. Continue through the explicit setup confirmation only while the scooter remains stationary and charger-disconnected.
6. If Capture reports a blocker, preserve the blocker evidence and stop rather than bypassing it.

## 5. Deterministic target correlation

Follow the app-guided sequence exactly:

1. **OFF 1** — scooter off.
2. **ON 1** — power scooter on when instructed.
3. **OFF 2** — power scooter off when instructed.
4. **ON 2** — power scooter on when instructed.

Acceptance rule:

- The repeated evidence must converge to one full CoreBluetooth peripheral identity under the accepted correlation contract.
- Zero candidates, multiple candidates, a tie, stale evidence, or an app-declared correlation failure is a stop condition.
- Do not break a tie using display name, RSSI, generic Tuya hints, service-name resemblance, or manual guesswork.
- A single repeatable result is only a **correlated Bluetooth target / scooter signal found** at this stage; it is not yet protocol-level proof of ES80 identity.

When the app presents the correlated target, perform the explicit target confirmation before continuing.

## 6. Passive discovery and observation

1. Allow the app to connect only through the accepted passive Experiment One path.
2. Do not interact with any control that would write a characteristic or command the scooter. The accepted build is expected to expose no such application path for this recipe.
3. Keep the app in the foreground and the scooter stationary, powered as instructed, and charger-disconnected.
4. Wait for the package-owned acquisition state to report **Observation Ready**.
5. After Observation Ready, allow at least **60 seconds** of the same-authority passive observation required by the accepted evidence contract.
6. Any on-screen timer is guidance only. Artifact authority comes from the package's accepted monotonic evidence/horizon rules, not from visually watching 60 seconds pass.

## 7. Finish, seal, and integrity

Only after the app indicates the required observation/horizon conditions are satisfied:

1. Finish the capture once.
2. Allow pending accepted chronology to settle and the immutable artifact to seal.
3. Do not restart or mutate the just-finished run while its artifact is being verified.
4. Require the final Share integrity path to report **Ready for analysis**.
5. If the integrity check fails, setup provenance is missing, foreground/continuity authority was lost, or the final bytes cannot be verified, do not promote the artifact. Keep the legitimate sealed evidence and start a fresh experiment only after the app/runbook conditions are restored.

## 8. Share and preserve the exact artifact

1. Use the primary **Share Capture** action from the accepted final Share path.
2. Transfer the exact retained JSON bytes that passed final integrity inspection; do not substitute a manually rebuilt JSON file, screenshot, copied text, or mutable temporary-path variant.
3. Save one untouched copy of the raw artifact.
4. Compute and record its SHA-256 before analysis.
5. Do not edit/reformat the preserved raw copy.

Record after successful collection:

- Capture artifact filename: `UNFILLED`
- Capture artifact SHA-256: `UNFILLED`
- Embedded source/build identity matched Approval block: `UNFILLED`
- Embedded recipe: `UNFILLED — must be ES80-FINGERPRINT-v1`
- Final integrity/analyzer readiness: `UNFILLED`
- Collection timestamp: `UNFILLED`

## 9. Immediate stop / failure conditions

Stop the experiment and do not call it accepted if any of the following occurs:

- wrong, unsigned, unverified, or unapproved app/build is running;
- exact-head Xcode result is not terminal SUCCESS for the accepted source SHA;
- signed installable or runtime provenance differs from the Approval block;
- research recipe is missing or not exactly `ES80-FINGERPRINT-v1`;
- app does not enter the dedicated research Capture path;
- charger is connected or charger-disconnected status becomes uncertain;
- scooter cannot remain stationary;
- any application characteristic write/vehicle command path appears or executes;
- Bluetooth permission/state or foreground integrity invalidates the run;
- OFF1 -> ON1 -> OFF2 -> ON2 correlation yields zero, multiple, tied, stale, or otherwise rejected candidates;
- the operator would need to guess which peripheral is the scooter;
- accepted target/session authority is lost and the app does not recover under its accepted rules;
- Observation Ready is never reached;
- the required post-ready observation horizon is not earned;
- Finish/seal/integrity cannot complete normally;
- final Share bytes are not the exact bytes that passed integrity inspection;
- artifact export/share fails or the resulting bytes cannot be independently retained and hashed;
- any unexpected scooter motion or unsafe physical behavior occurs.

A stopped/failed attempt is evidence about the tooling, not permission to relax the gate.

## 10. After the first accepted artifact

1. Preserve the raw artifact unchanged.
2. Run the accepted offline analyzer against a copy or read-only subject.
3. Identify only what the artifact actually supports: services, characteristics, notifications/indications, cadence, raw values, timing, provenance, and correlations.
4. State unknowns explicitly.
5. Generate the next smallest safe evidence-gathering experiment from the remaining unknowns.
6. Reopen deferred post-capture release-grade hardening in parallel with physical-evidence-driven Battery / Power / Speed / Range / Dashboard work.

## GO transition rule

Changing this document from **NO-GO** to **GO** is a deliberate evidence checkpoint, not a prediction. The GO revision must name the exact accepted source SHA, terminal Xcode run, signed installable SHA-256, intended-device verification, procedure version, and all required stop conditions above. Until then: **DO NOT RUN THE PHYSICAL EXPERIMENT.**
