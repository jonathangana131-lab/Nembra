# ES80 Signed Field Candidate Production — V14

Status: **CANDIDATE PRODUCTION / EVIDENCE ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

## Canonical production chain

`scripts/ci/xcode27_signed_field_candidate.sh` produces one real signed/exported iPhone Capture candidate from a fresh detached worktree at the exact source SHA. It stamps the V14 Capture build tuple plus `NembraCaptureFieldRecipe=ES80-FINGERPRINT-v1`, exports exactly one top-level IPA, passes that exact IPA to the canonical post-build inspector `scripts/ci/es80_signed_field_artifact_evidence.py`, and then rechecks the retained evidence relationships and signed launch marker.

The field-recipe Info.plist value is launch routing only. It lets an accepted Release field build opened from the iPhone Home Screen enter the Capture instrument without a DEBUG-only Xcode launch argument. It cannot grant physical authority; the package field gate remains independently fail-closed.

The producer does not create another package field-evidence schema. The inspector-owned machine-readable subjects are published together under `inspection/`:

- `inspection/NembraCaptureExternalBuildRecord.json` — schema-v3 exact executable/Info.plist/build rendezvous;
- `inspection/NembraCaptureFieldBuildEvidenceRecord.json` — closed-world package field-build record binding the exact signed IPA digest;
- `inspection/NembraCaptureSignedFieldArtifactInspection.json` — non-authorizing platform/signing/provisioning diagnostics;
- `inspection/build-evidence/NembraField.ipa` — retained exact exported signed installable.

Producer-owned release provenance remains outside `inspection/` at the candidate root. The inspector must receive an absent `inspection/` path so its failure-atomic/no-replace publication contract remains intact.

## Required external inputs

The current producer requires:

- `NEMBRA_DEVELOPMENT_TEAM` — one canonical 10-character Apple TeamIdentifier;
- `NEMBRA_EXPORT_OPTIONS_PLIST` — an existing Xcode export-options plist supplied by the field operator/release process;
- `NEMBRA_INTENDED_FIELD_DEVICE_UDID` — the intended field iPhone identifier, used only to verify provisioning eligibility;
- optional `NEMBRA_ALLOW_PROVISIONING_UPDATES=0|1`, defaulting to `0`.

The intended-device value must be nonblank, bounded to 128 UTF-8 bytes, and contain no whitespace/control characters. It is forwarded to the canonical inspector for the provisioning-profile device-membership check and is deliberately not written into retained candidate evidence or `field-candidate-environment.txt`.

A successful provisioning check proves only that the retained profile authorizes the supplied intended device when device eligibility applies. It does not prove that the IPA was installed or launched on that iPhone.

## Exact external export policy

`NEMBRA_EXPORT_OPTIONS_PLIST` is external release input. The producer does not guess or synthesize an Xcode export method.

Before archive/export it:

1. resolves a unique candidate output directory from the source SHA plus generated build-instance UUID unless a one-shot `ARTIFACTS_DIR` is supplied;
2. physically canonicalizes that path before safety decisions so lexical traversal or existing symlink ancestors cannot bypass root checks;
3. rejects `/`, the repository root, or any already-existing candidate directory;
4. requires an in-repository candidate directory to already be Git-ignored;
5. copies the supplied export-options plist to the candidate root as `ExportOptions.plist`;
6. validates that retained snapshot as a plist;
7. rejects a snapshot `teamID` that disagrees with `NEMBRA_DEVELOPMENT_TEAM`;
8. hashes the exact retained snapshot;
9. passes that retained snapshot — not the caller's mutable original path — to `xcodebuild -exportArchive`;
10. re-hashes the retained snapshot after export and fails closed if its bytes changed.

The exact export policy used for the retained IPA is therefore reviewable evidence rather than operator recollection or a mutable external path.

## Failure-atomic evidence topology

The producer and inspector have separate ownership boundaries inside one candidate root:

- producer-owned `ExportOptions.plist`;
- producer-owned `logs/xcodebuild-archive.log`;
- producer-owned `logs/xcodebuild-export.log`;
- producer-owned `field-candidate-environment.txt`;
- inspector-owned `inspection/`, which must not exist before inspector invocation.

The canonical inspector stages its evidence in a temporary sibling and atomically publishes `inspection/` only after all signed-IPA checks succeed. An existing destination is never replaced.

This separation prevents export logs or policy provenance from accidentally defeating the inspector's failure-atomic evidence boundary.

## macOS Bash 3.2 portability

The producer runs under `/bin/bash` with `set -euo pipefail`. The macOS system Bash can fail on optionally empty arrays under nounset.

The current producer therefore avoids those forms:

- provisioning updates are handled by an explicit `run_xcodebuild` branch rather than an optionally empty argument array;
- exact exported-IPA selection is performed by Python and must find exactly one regular top-level `.ipa` rather than relying on nullglob/empty arrays;
- archive/export pipeline failure is checked directly around each `run_xcodebuild ... | tee ...` command.

The source-contract tests pin these portability constraints.

## Immutable source and build identity

The invocation checkout must be clean, including non-ignored untracked files. The producer resolves exact `HEAD^{commit}`, then creates a fresh detached worktree at that SHA for the real build.

Before and after archive/export, the detached worktree must still be clean and at the exact source SHA.

The archive injects:

- `NembraCaptureBuildIdentifier=Capture Build V14-<12-char source SHA>`;
- a fresh lowercase UUID `NembraCaptureBuildInstanceID`;
- exact `NembraCaptureBuildCommitSHA`;
- `NembraCaptureFieldRecipe=ES80-FINGERPRINT-v1`.

These declarations are provenance/rendezvous evidence. They are not physical authorization.

## Signed-device checks inherited from the canonical inspector

The final exported IPA must satisfy the current canonical field-artifact inspector, including:

- iPhoneOS rather than Simulator platform;
- strict non-ad-hoc code signing;
- exact Nembra bundle identifier;
- canonical Apple TeamIdentifier;
- actual leaf signing certificate present in the provisioning profile `DeveloperCertificates`;
- effective signed entitlements authorized by the provisioning profile, with wildcard semantics limited to explicitly supported entitlement keys;
- unexpired provisioning profile;
- exact application-identifier/team relationship;
- intended-device authorization unless the profile provisions all devices;
- exact source/build-instance/build-label rendezvous;
- exact executable and raw Info.plist SHA-256 values;
- exact retained IPA digest;
- `ES80-FINGERPRINT-v1` / `V14` procedure identity;
- failure-atomic publication of the retained evidence directory.

These facts remain evidence. They do not decide that the candidate was independently accepted, installed on the intended field iPhone, or authorized for Experiment One.

## Producer post-inspection checks

After canonical inspection succeeds, the producer re-verifies the retained subjects instead of trusting path names alone. It requires:

- the exact closed-world field-build evidence shape;
- the exact closed-world signing-inspection shape;
- matching source SHA, build identifier, build-instance ID, recipe, and procedure across evidence;
- the requested development team to match signing inspection;
- the signing inspection to remain explicitly non-authorizing;
- exact external-record, field-record, IPA, executable, and Info.plist digest relationships;
- the retained IPA to contain exactly one top-level signed app `Info.plist` with `NembraCaptureFieldRecipe=ES80-FINGERPRINT-v1`;
- those exact raw Info.plist bytes to match the digest already bound by field evidence.

The launch-marker recheck is not a second authority system. It confirms that the retained signed subject already bound by canonical evidence contains the routing marker required by the installed Release flow.

## Durable producer provenance

The candidate root retains:

- exact `ExportOptions.plist` bytes and SHA-256;
- `logs/xcodebuild-archive.log`;
- `logs/xcodebuild-export.log`;
- `field-candidate-environment.txt` containing source SHA, build identifier, build-instance ID, development team, provisioning-update setting, field/experiment recipe, export-policy digest, relative log/evidence paths, procedure identity, Xcode version, signing-inspection authority label, and `physical_authorization=not-granted`;
- the inspector-owned immutable `inspection/` subtree described above.

The intended-device identifier is deliberately absent from retained producer provenance and inspector evidence.

## What producer success does not prove

A successful run does **not** prove:

- independent Nembra acceptance of the retained IPA/evidence;
- that the selected export policy is the finally accepted field installation route;
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

The final Capture software composition still requires terminal exact-head Apple acceptance plus real screenshot/accessibility/performance review. That exact source must then produce the signed IPA through this chain. The exact retained IPA and evidence subjects require independent acceptance. Only an independently controlled authorization key over the exact accepted subjects may then be consumed by the package-owned field gate, followed by a deliberate final runbook GO and fresh exact-head product acceptance.

Until every applicable gate is closed:

**PHYSICAL EXPERIMENT ONE / FIRST REAL ES80 CAPTURE: DO NOT RUN / NO-GO.**
