# ES80 Signed Field Candidate Production — V14

Status: **CANDIDATE PRODUCTION / EVIDENCE ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

## Canonical production chain

`scripts/ci/xcode27_signed_field_candidate.sh` produces the real signed/exported iPhone Capture candidate. It builds from a fresh detached worktree at the exact source SHA, stamps the exact V14 Capture build tuple plus `NembraCaptureFieldRecipe=ES80-FINGERPRINT-v1`, exports one IPA, and passes that IPA into the canonical post-build inspector.

The field-recipe Info.plist value is launch routing only. It lets an accepted Release field build opened from the iPhone Home Screen enter the Capture instrument without a DEBUG-only Xcode launch argument. It cannot grant physical authority; the package field gate remains independently fail-closed.

The intended field-device identifier is verification-only input. The producer accepts only an absolute private file path through `NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE`; the file must be a regular non-symlink private input. `scripts/ci/es80_signed_field_artifact_private_runner.py` opens and validates that file through its descriptor boundary, then invokes the canonical inspector in-process so the raw identifier is not placed in the producer or runner OS-visible process arguments. The raw identifier must never be retained in logs, evidence records, artifact names, hashes, or environment provenance.

The producer does not create another field evidence schema. The machine-readable inspector subjects are published failure-atomically under the candidate's `inspection/` directory:

- `inspection/NembraCaptureExternalBuildRecord.json` — schema-v3 exact executable/Info.plist/build rendezvous;
- `inspection/NembraCaptureFieldBuildEvidenceRecord.json` — closed-world package field-build record binding the exact signed IPA digest;
- `inspection/NembraCaptureSignedFieldArtifactInspection.json` — non-authorizing platform/signing/provisioning/launch diagnostics;
- `inspection/build-evidence/NembraField.ipa` — retained exact exported signed installable.

The producer-owned export-policy snapshot, logs, and environment provenance remain siblings of `inspection/`; they are not written into the inspector's failure-atomic publication directory.

## Exact external export policy

`NEMBRA_EXPORT_OPTIONS_PLIST` is an external release input. The producer deliberately does not guess or synthesize an Xcode export method.

Before the public candidate is published it now:

1. resolves a unique final evidence directory for the exact source/build-instance;
2. physically canonicalizes that path before safety decisions so lexical `..` or existing symlink ancestors cannot bypass root checks;
3. refuses `/`, the repository root, or any already-existing final candidate directory;
4. requires an in-repository final candidate directory to already be Git-ignored;
5. creates only the candidate parent recursively and keeps the public final candidate path absent throughout archive, export, private intended-device inspection, and exact-byte crosschecks;
6. copies the supplied export-options plist into producer-owned temporary `WORK_ROOT`, validates that exact snapshot as a plist, rejects a snapshot `teamID` that disagrees with `NEMBRA_DEVELOPMENT_TEAM`, hashes it, and passes that exact snapshot — not the caller's mutable original path — to `xcodebuild -exportArchive`;
7. retains archive/export logs and canonical inspector output in temporary producer-owned storage until every build, inspection, source-integrity, and exact-byte check has succeeded;
8. re-hashes the export-policy snapshot after export and fails closed if its bytes changed;
9. only after all prepublication phases succeed, attempts to create the hidden sibling staging directory on the destination filesystem; process-local staging ownership starts false and becomes true only after this invocation's `mkdir` succeeds, so an invocation that loses the staging-path race refuses reuse and its cleanup cannot delete staging it never created;
10. assembles the complete final layout only in that owned staging directory: exact `ExportOptions.plist`, archive/export logs, canonical `inspection/`, and environment provenance;
11. recursively re-hashes the staged inspector tree and re-hashes the staged ExportOptions bytes to prove the final staging copy still matches the already-verified source evidence;
12. publishes that complete staging directory as the public candidate in one exclusive macOS `renamex_np(..., RENAME_EXCL)` operation, which refuses replacement if another candidate appeared concurrently;
13. clears process-local staging ownership immediately after the exclusive rename succeeds, before clearing the staging pathname, so later cleanup cannot target the published candidate.

This makes the candidate-root no-mix boundary, staging cleanup authority, and the actual export policy used for the retained IPA mechanical and reviewable. A producer failure before the final exclusive rename leaves the public candidate path absent rather than exposing a partial final directory. A process that never successfully created the hidden staging directory has no cleanup authority over it, and a concurrent final publisher cannot be silently replaced.

## macOS field-machine portability

The producer runs under `/bin/bash` with `set -u`. macOS still ships an older Bash where optional empty arrays can fail as unbound variables.

Two optional-array hazards are therefore intentionally absent:

- provisioning updates are a validated `0|1` input consumed by an explicit `run_xcodebuild` branch; there is no optionally empty `PROVISIONING_ARGS` array;
- exact exported-IPA selection is performed by Python and must find exactly one regular top-level `.ipa`; there is no nullglob/empty `IPA_FILES` array.

The source-contract tests explicitly reject both older array forms.

## Durable production evidence

The candidate directory retains:

- exact `ExportOptions.plist` bytes and SHA-256;
- `logs/xcodebuild-archive.log`;
- `logs/xcodebuild-export.log`;
- the canonical inspector outputs under the immutable `inspection/` subtree listed above;
- `field-candidate-environment.txt`, including source SHA, build identifier, build-instance ID, requested/verified team, provisioning-update setting, field-launch recipe, export-options digest, recipe/procedure, log paths, `inspection_directory=inspection`, and `physical_authorization=not-granted`.

The archive and export commands are piped through `tee`; failure from either Xcode or log capture is a producer failure. The detached source worktree is rechecked after archive/export and must still be the exact clean source SHA.

Neither the raw intended field-device identifier nor its private input-file path is durable candidate evidence or environment provenance.

## Signed-device checks inherited from the canonical inspector

The final exported IPA must satisfy the current canonical field-artifact inspector, including:

- exact field launch recipe;
- `iPhoneOS` rather than Simulator platform;
- strict code signing;
- leaf signing certificate membership in the embedded provisioning profile's `DeveloperCertificates`;
- matching signing/provisioning team and application identity;
- effective signed entitlements authorized by the provisioning profile;
- wildcard provisioning only for the inspector's explicit closed-world supported entitlement family rather than generic wildcard treatment for arbitrary keys;
- an unexpired embedded provisioning profile;
- authorization of the verification-only intended field-device identifier, unless `ProvisionsAllDevices` is explicitly true;
- exact retained IPA, executable, and raw Info.plist digests.

Those facts remain evidence. They do not decide that the candidate was independently accepted, prove that the retained IPA is the bytes actually installed/running on the intended iPhone, or authorize Experiment One.

## What producer success does not prove

A successful run does **not** prove:

- independent Nembra acceptance of the retained IPA/evidence;
- that the selected export policy is the accepted field installation route;
- that the retained IPA was installed or launched on the intended iPhone;
- that an independently controlled authorization key approved these exact subjects;
- that the production public trust root is configured;
- that the package physical execution gate is GO;
- that the V14 physical runbook is GO;
- physical AOVOPRO ES80 identity or RF completeness;
- GATT/Tuya/DP, battery, voltage, current, power, speed, regen, or command semantics;
- command acknowledgement or safe characteristic write authority.

No application Bluetooth characteristic-value write path is added by this producer.

## Remaining physical gate

The surviving final Capture software composition still requires terminal exact-head Apple acceptance plus real screenshot/accessibility/performance review. That exact source must then produce the signed IPA through this chain. The exact retained IPA and evidence subjects require independent acceptance. Only an independently controlled authorization key over the exact accepted subjects may then be consumed through the package-owned verified-admission boundary, followed by a deliberate final runbook GO and fresh exact-head product acceptance.

Until every applicable gate is closed:

**PHYSICAL EXPERIMENT ONE / FIRST REAL ES80 CAPTURE: DO NOT RUN / NO-GO.**
