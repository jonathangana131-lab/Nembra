# ES80 Signed Field Candidate Production — V14

Status: **CANDIDATE PRODUCTION / EVIDENCE ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

## Canonical production chain

`scripts/ci/xcode27_signed_field_candidate.sh` produces one real signed/exported iPhone Capture candidate. It builds from a fresh detached worktree at the exact source SHA, stamps the exact V14 Capture build tuple plus `NembraCaptureFieldRecipe=ES80-FINGERPRINT-v1`, exports exactly one IPA, and passes that IPA into the canonical post-build inspector `scripts/ci/es80_signed_field_artifact_evidence.py`.

The field-recipe Info.plist value is launch routing only. It lets a Release field build opened from the iPhone Home Screen enter Capture without a DEBUG-only Xcode launch argument. It cannot grant physical authority; the package field gate remains independently fail-closed.

The producer does not create another field-evidence schema. The canonical inspector still owns:

- `NembraCaptureExternalBuildRecord.json` — schema-v3 exact executable/Info.plist/build rendezvous;
- `NembraCaptureFieldBuildEvidenceRecord.json` — closed-world package field-build record binding the exact signed IPA digest;
- `NembraCaptureSignedFieldArtifactInspection.json` — non-authorizing platform/signing/provisioning diagnostics;
- `build-evidence/NembraField.ipa` — retained exact exported signed installable.

## Required external inputs

The producer requires:

- `NEMBRA_DEVELOPMENT_TEAM` — canonical Apple TeamIdentifier;
- `NEMBRA_EXPORT_OPTIONS_PLIST` — caller-supplied export policy;
- `NEMBRA_FIELD_DEVICE_UDID` — the intended field iPhone identifier, used only to verify that the embedded provisioning profile actually covers that phone.

`NEMBRA_FIELD_DEVICE_UDID` is deliberately **verification-only**. The producer does not print it, pass it to `xcodebuild`, store it in Info.plist, write it to `field-candidate-environment.txt`, or add it to the package field-evidence record. The canonical inspector receives it only through `--intended-device-udid` and fails closed if the profile does not authorize that device (unless the accepted profile is an all-devices profile). The inspector also never persists or prints the UDID.

This proves provisioning coverage without turning a device identifier into release evidence or app authority.

## Exact external export policy

`NEMBRA_EXPORT_OPTIONS_PLIST` is an external release input. The producer deliberately does not guess or synthesize an Xcode export method.

Before archive/export it:

1. physically canonicalizes the requested final candidate path before safety decisions;
2. refuses `/`, the repository root, or any existing final/staging candidate directory;
3. requires an in-repository candidate directory to already be Git-ignored;
4. copies the supplied export-options plist into temporary release evidence as `ExportOptions.plist`;
5. validates that exact snapshot as a plist;
6. rejects a snapshot `teamID` that disagrees with `NEMBRA_DEVELOPMENT_TEAM`;
7. hashes the exact snapshot;
8. passes that snapshot — not the caller's mutable original path — to `xcodebuild -exportArchive`;
9. re-hashes it after export and again after final candidate assembly, failing closed if its bytes changed.

The final candidate therefore carries the exact export-policy bytes actually consumed by Xcode.

## Bash 3.2 / field-Mac portability

The producer runs under `/bin/bash` with `set -euo pipefail`. macOS still ships an older Bash where optionally empty arrays can fail under `set -u`.

Two hazards are intentionally removed:

- provisioning updates are a validated `0|1` input consumed by an explicit `run_xcodebuild` branch; there is no optionally empty `PROVISIONING_ARGS` array;
- exported IPA selection is performed by Python and must find exactly one regular top-level `.ipa`; there is no nullglob/empty `IPA_FILES` array.

Archive and export output are captured through `tee`, and failure from either Xcode or log capture is a producer failure.

## Two-stage evidence publication

The canonical inspector owns failure-atomic publication of its own evidence directory and therefore requires a destination that does not already exist. The producer must not pre-create that destination merely to hold logs.

The current topology is:

1. archive/export logs and the exact ExportOptions snapshot remain under the temporary work root;
2. the canonical inspector publishes one complete temporary inspector-evidence directory under that work root;
3. the producer rechecks exact external-record / field-record / retained-IPA digest relationships;
4. a separate final staging directory on the **same filesystem as the requested final destination** is assembled from inspector output + ExportOptions + logs + environment evidence;
5. macOS `renamex_np(..., RENAME_EXCL)` publishes that complete directory atomically without replacing any existing destination.

A crash or concurrent worker cannot expose a half-assembled final candidate or overwrite an already-published candidate. Cleanup removes only temporary/staging state; once the exclusive rename succeeds, published evidence is no longer a cleanup target.

## Durable candidate evidence

The final candidate directory retains:

- exact `ExportOptions.plist` bytes and SHA-256;
- `logs/xcodebuild-archive.log`;
- `logs/xcodebuild-export.log`;
- the canonical inspector outputs listed above;
- `field-candidate-environment.txt`, containing source SHA, build identifier, build-instance ID, requested signing team, provisioning-update setting, field-launch recipe, export-options digest, recipe/procedure, log paths, and `physical_authorization=not-granted`.

The intended device UDID is intentionally absent from that durable evidence.

## Signed-device checks inherited from the canonical inspector

The final exported IPA must satisfy the current canonical field-artifact inspector, including iPhoneOS rather than Simulator platform, strict all-architecture code-sign verification, exact bundle signing identifier, canonical TeamIdentifier/CDHash/authority chain, the actual leaf signing certificate being authorized by `DeveloperCertificates`, effective signed entitlements being permitted by the embedded profile, unexpired provisioning, exact application/team binding, intended-device authorization, exact build/recipe declarations, and exact retained IPA/executable/raw-Info.plist digests.

Those facts remain evidence. They do not decide that the candidate was independently accepted, installed, launched, or authorized for Experiment One.

## What producer success does not prove

A successful run does **not** prove:

- independent Nembra acceptance of the retained IPA/evidence;
- that the selected export policy is the accepted installation route;
- that the retained IPA was actually installed or launched on the intended iPhone;
- that an independently controlled authorization key approved these exact subjects;
- that the production P-256 public trust root is configured;
- that a verified authorization has been admitted by the package field gate;
- that the V14 physical runbook is GO;
- physical AOVOPRO ES80 identity or RF completeness;
- GATT/Tuya/DP, battery, voltage, current, power, speed, regen, or command semantics;
- command acknowledgement or safe characteristic-write authority.

No application Bluetooth characteristic-value write path is added by this producer.

## Remaining physical gate

The surviving final Capture composition still requires terminal exact-head Apple acceptance plus actual screenshot/accessibility/performance review. That exact source must then produce the signed IPA through this chain. The exact retained IPA and evidence subjects require independent acceptance. Only an independently controlled authorization key over the accepted subjects may be verified and converted into the package's non-forgeable field-admission capability, followed by deliberate app integration and final runbook GO.

Until every applicable gate is closed:

**PHYSICAL EXPERIMENT ONE / FIRST REAL ES80 CAPTURE: DO NOT RUN / NO-GO.**
