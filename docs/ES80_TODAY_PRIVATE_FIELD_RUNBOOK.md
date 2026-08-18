# ES80 TODAY Private Field Runbook — RETIRED / NON-AUTHORIZING

Status: **RETIRED. PHYSICAL STATUS: NO-GO. DO NOT USE THIS HISTORICAL RUNBOOK TO AUTHORIZE OR START AN ES80 PHYSICAL ATTEMPT.**

The old private TODAY / `ES80-FINGERPRINT-v1` procedure has been superseded. Its former frozen source pin, retained-IPA workflow, signing route, Final-GO record, operator attestation, and executable-bundle instructions are historical evidence only and are preserved in Git history rather than repeated here as operational instructions.

The current Nembra Capture physical-authorization path is **`ES80-AUTHENTICATED-STATIONARY-v1`**. Its invariant physical gate is documented in `docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md`, but all mutable coordination facts — exact software head, accepted checks, private intended-device authority, signed install subject, and any Final-GO evidence — must be resolved from fresh live GitHub state before use.

`docs/ES80_TODAY_FINAL_GO_OPERATOR_ATTESTATION.md` is also retired and non-authorizing. A reference to that file, an old TODAY validator, an old signed IPA, an old retained artifact, an old target UUID, or an ancestor exact-head success must never be reconstructed into current physical authority.

Until the authenticated-stationary control plane explicitly produces an accepted Final-GO result for one exact accepted Capture candidate:

- **PHYSICAL STATUS: NO-GO**;
- do not scan the ES80 for the experiment;
- do not run the retired passive TODAY workflow;
- do not reuse or rebuild an old `NembraField.ipa` as a substitute field subject;
- do not use the historical C7D09A22 CoreBluetooth UUID as current target authority;
- do not substitute Simulator, package-only, ancestor, skipped, queued, or child-only evidence for exact-head app acceptance;
- do not issue Bluetooth writes, DP queries/controls, reset, unbind, OTA, or scooter commands;
- do not promote opaque application payloads into battery, speed, voltage, current, power, mode, odometer, command-acknowledgement, or other telemetry semantics.

## Current legal next transition

A future field attempt may proceed only from the live authenticated-stationary lineage after all of its current software, provenance, private intended-device, signed-install, and Final-GO gates have been accepted on the exact candidate named by that authority.

The physical procedure remains stationary and observational/read-only. The minimum accepted evidence target is a legitimate already-bound Tuya/SmartLife authenticated application session for the freshly correlated scooter target, genuine accepted application evidence under the final reviewed source contract, and accepted continuity beyond the historical approximately-30-second rejection region with a target of at least 45 seconds. The exact current gate, stop conditions, evidence-source contract, and artifact requirements remain authoritative over this retirement marker.

If live state is ambiguous, stale, red, skipped, queued, or missing a required authority-bearing gate, remain **NO-GO**. Never recover an older commit merely because its historical procedure could emit `GO`.

## Historical recovery

The retired TODAY procedure remains available through Git history for audit, regression investigation, and provenance review. Historical text must not be copied into a new operational runbook without a fresh review that explicitly re-establishes every authority boundary required by the current authenticated-stationary control plane.
