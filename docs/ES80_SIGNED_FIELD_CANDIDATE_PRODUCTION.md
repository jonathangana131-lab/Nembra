# ES80 Signed Field Candidate Production — V14

Status: **CANDIDATE PRODUCTION / EVIDENCE ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

## Canonical production chain

`scripts/ci/xcode27_signed_field_candidate.sh` produces one real signed/exported iPhone Capture candidate from a fresh detached worktree at the exact source SHA. It stamps the exact V14 Capture build tuple plus `NembraCaptureFieldRecipe=ES80-FINGERPRINT-v1`, exports exactly one top-level IPA, passes that IPA to the canonical post-build inspector `scripts/ci/es80_signed_field_artifact_evidence.py`, and then cross-checks the retained evidence subjects and exact retained IPA.

The field-recipe Info.plist value is launch routing only. It lets an accepted Release field build opened from the iPhone Home Screen enter the Capture instrument without a DEBUG-only Xcode launch argument. It cannot grant physical authority; the package field gate remains independently fail-closed.

The producer does not create another field-evidence schema. The canonical inspector owns one failure-atomic child directory named `inspection/` inside the one-shot candidate root. Its machine-readable subjects are:

- `inspection/NembraCaptureExternalBuildRecord.json` — schema-v3 exact executable/Info.plist/build rendezvous;
- `inspection/NembraCaptureFieldBuildEvidenceRecord.json` — closed-world package field-build record binding the exact signed IPA digest;
- `inspection/NembraCaptureSignedFieldArtifactInspection.json` — non-authorizing signed-device/platform/provisioning diagnostics;
- `inspection/build-evidence/NembraField.ipa` — retained exact exported signed installable.

Producer-owned release provenance remains outside `inspection/` so creating logs or policy snapshots cannot pre-create the inspector destination and defeat its atomic no-replace publication contract.

## Intended field device

The current producer requires `NEMBRA_INTENDED_FIELD_DEVICE_UDID` as verification-only input for the intended field iPhone.

Before spending the archive/export cycle, the producer requires the value to be nonblank, at most 128 UTF-8 bytes, free of leading/trailing whitespace, and free of whitespace/control characters. It deliberately does not guess one fixed Apple identifier shape.

The value is then forwarded to the canonical inspector as `--intended-device-udid`. The inspector uses it only to require that a device-scoped provisioning profile authorizes the intended target where applicable. The identifier is not a retained evidence field, is not included in the producer environment record, and must not be used to derive artifact names, build-instance identity, or physical authority.

**Known privacy hardening still open:** the current shell producer places this verification-only value in the inspector child process argument vector. That does not persist it into Nembra evidence, but it can make the raw value observable to local process inspection during that invocation. The active V14 hardening direction is to pass only a private mode-0600 file path across the process boundary and read the raw identifier inside a narrow runner that invokes the same canonical inspector in-process. Until that stronger path is composed and accepted, do not describe the current producer as process-argv private.

A producer success does not prove that the IPA was installed or launched on that iPhone.

## Failure-atomic output topology

Every run resolves a unique one-shot candidate root from the exact source SHA plus build-instance UUID unless the caller supplies one one-shot `ARTIFACTS_DIR`.

The producer:

1. physically canonicalizes the requested candidate root before safety decisions;
2. refuses `/`, the repository root, or any already-existing destination;
3. requires an in-repository candidate root to already be Git-ignored;
4. creates only producer-owned paths such as `logs/` and `ExportOptions.plist` before signed-IPA inspection;
5. keeps `inspection/` nonexistent until the canonical inspector is invoked;
6. lets the inspector stage and atomically publish `inspection/` only after its full validation succeeds.

This is the important no-replace boundary: the candidate root may already exist because it contains producer provenance, but the inspector-owned `inspection/` child must not.

## Exact external export policy

`NEMBRA_EXPORT_OPTIONS_PLIST` is external release input. The producer deliberately does not guess or synthesize an Xcode export method.

Before archive/export it:

1. copies the supplied export-options plist into the one-shot candidate root as `ExportOptions.plist`;
2. validates the retained snapshot as a plist;
3. rejects a snapshot `teamID` that disagrees with `NEMBRA_DEVELOPMENT_TEAM`;
4. requires `method`, when present, to be a non-empty string;
5. hashes the exact retained snapshot;
6. passes that retained snapshot — not the caller's mutable original path — to `xcodebuild -exportArchive`;
7. re-hashes it after export and fails closed if its bytes changed.

The actual export policy used for the retained IPA is therefore reviewable evidence rather than operator recollection or a mutable external pathname.

## macOS field-machine portability

The producer runs under `/bin/bash` with `set -euo pipefail`. macOS system Bash remains old enough that optional empty arrays under nounset are unsafe.

The current producer therefore avoids those forms:

- provisioning updates are a validated `0|1` input consumed through one explicit `run_xcodebuild` branch;
- exact exported-IPA selection is performed by Python and must find exactly one regular top-level `.ipa`;
- no optional `PROVISIONING_ARGS` or `IPA_FILES` arrays are required.

Archive/export output is retained through `tee` under `pipefail`, so either Xcode failure or pipeline failure makes candidate production fail.

## Exact source and build rendezvous

The invocation checkout must be clean. The actual Release archive is additionally built from a fresh detached worktree at `SOURCE_SHA`.

The producer stamps:

- `NembraCaptureBuildIdentifier=Capture Build V14-<12-hex source prefix>`;
- one canonical lowercase UUID `NembraCaptureBuildInstanceID`;
- exact lowercase 40-hex `NembraCaptureBuildCommitSHA`;
- `NembraCaptureFieldRecipe=ES80-FINGERPRINT-v1`.

After archive/export, the detached worktree must still be at the same exact SHA and clean. Source mutation during the production cycle invalidates the candidate.

## Canonical signed-device checks

The canonical inspector verifies the final IPA as evidence, not authority. Its current checks include:

- exactly one safe top-level `Payload/*.app` bundle;
- no ambiguous/unsafe ZIP paths or unsupported symbolic-link archive members;
- physical iPhone platform declarations rather than Simulator;
- strict non-ad-hoc code signature and canonical team identity;
- signing leaf certificate authorized by the embedded provisioning profile;
- effective signed entitlements permitted by the profile, with wildcard interpretation restricted to the explicitly accepted entitlement vocabulary;
- unexpired provisioning profile and matching application identifier;
- intended-device authorization for device-scoped profiles without persisting the intended-device identifier;
- exact executable, raw Info.plist, source SHA, build identifier, build-instance, recipe, and procedure rendezvous;
- exact SHA-256 binding between the external-build record, canonical field-build evidence, signing inspection, and retained IPA.

After canonical inspection, the producer independently cross-checks those digest relationships against the current closed-world inspection schema. It also reopens only the already-inspected retained IPA to require the exact Home-Screen launch recipe marker. That marker remains routing, never physical authority.

## Durable production evidence

The one-shot candidate root retains producer provenance:

- `ExportOptions.plist` plus its SHA-256 in `field-candidate-environment.txt`;
- `logs/xcodebuild-archive.log`;
- `logs/xcodebuild-export.log`;
- `field-candidate-environment.txt`, including exact source/build tuple, requested development team, provisioning-update setting, field recipe, export-policy digest, log paths, recipe/procedure identity, and `physical_authorization=not-granted`;
- canonical inspector-owned `inspection/` evidence listed above.

The verification-only intended-device identifier is deliberately absent from retained producer/evidence fields.

## What producer success does not prove

A successful run does **not** prove:

- independent Nembra acceptance of the retained IPA/evidence;
- that the selected export policy is the finally accepted installation route;
- that the retained IPA was installed or successfully launched on the intended iPhone;
- that the process-argv privacy hardening described above has been accepted;
- that an independently controlled authorization key approved these exact subjects;
- that the production public trust root is configured;
- that the package physical execution gate is GO;
- that the V14 physical runbook is GO;
- physical AOVOPRO ES80 identity or RF completeness;
- GATT/Tuya/DP, battery, voltage, current, power, speed, regen, or command semantics;
- command acknowledgement or safe characteristic-write authority.

No application Bluetooth characteristic-value write path is added by this producer.

## Remaining physical gate

The final composed Capture source still requires terminal exact-head Apple acceptance plus real screenshot/accessibility/performance review. That exact accepted source must then produce the signed IPA through this chain. The exact retained IPA and evidence subjects require independent acceptance. Only an independently controlled authorization key over the exact accepted subjects may then be consumed by the package-owned field gate, followed by a deliberate final runbook GO and fresh exact-head product acceptance.

Until every applicable gate is closed:

**PHYSICAL EXPERIMENT ONE / FIRST REAL ES80 CAPTURE: DO NOT RUN / NO-GO.**
