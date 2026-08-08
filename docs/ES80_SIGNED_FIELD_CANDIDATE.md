# ES80 Signed Field Candidate — V14

Status: **SIGNED-CANDIDATE TOOLING ONLY / PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

## Purpose

The current Capture flagship can produce exact unsigned Simulator provenance, but Simulator bytes cannot authorize a physical ES80 experiment. `scripts/field/xcode27_signed_capture_candidate.sh` closes the next mechanical gap: on a trusted local Mac with Xcode 27 and a configured Apple Developer signing identity, it produces one exact signed iOS Capture candidate and preserves post-sign evidence without feeding the final executable digest back into the signed app bundle.

This script is deliberately **not** a GO button. A successful archive, valid code signature, successful optional device installation, matching schema-v3 record, or exact digest still requires independent product acceptance before the package field gate/runbook may be evolved to GO.

## Required local inputs

Run only from the exact clean Capture candidate checkout intended for review.

Required:

- macOS with Xcode 27 selected;
- an Apple Developer account/signing identity already usable by Xcode;
- `NEMBRA_DEVELOPMENT_TEAM` set to the intended exact 10-character Apple Developer Team ID;
- a completely clean Git worktree, including no non-ignored untracked files.

The team environment variable is a requested build input only. After archive, the script reads `TeamIdentifier` from the final app's code signature and fails unless that actual signed identity exactly matches the requested team. Candidate evidence records the verified code-signature team, not an unchecked caller declaration.

Optional:

- `NEMBRA_INSTALL_DEVICE_ID` may name one `devicectl` device identifier. If supplied, the script attempts to install the exact archived signed `.app` after all evidence checks. Installation success is only installability evidence; it does not open the physical Capture field gate. The device identifier and raw `devicectl` output are not retained in the evidence bundle.
- `ARTIFACTS_DIR` and `DERIVED_DATA` may be overridden. If either points inside the repository, that path must already be Git-ignored; otherwise the script fails before creating output.

The script does not request, print, commit, or manufacture signing certificates/private keys/provisioning secrets.

## Exact production sequence

The script:

1. resolves exact `HEAD^{commit}` and requires one lowercase 40-hex commit;
2. rejects tracked changes and all non-ignored untracked files before writing output;
3. constrains any in-repository artifact/DerivedData path to a pre-existing Git-ignored location, preventing generated files from entering the exact-source claim after preflight;
4. generates the human-readable V14 build label and one fresh lowercase UUID build-instance rendezvous ID before the build;
5. archives `Nembra` for generic iOS Release with automatic signing under the explicitly supplied development team;
6. re-checks the repository after archive and rejects any new non-ignored source/worktree mutation;
7. injects and then re-reads `NembraCaptureBuildIdentifier`, `NembraCaptureBuildInstanceID`, and `NembraCaptureBuildCommitSHA`, requiring exact equality plus the expected bundle identifier;
8. rejects any executable-digest provenance record found inside the app bundle;
9. runs strict `codesign` verification, reads the final code-signature `TeamIdentifier`, and requires it to exactly equal `NEMBRA_DEVELOPMENT_TEAM`;
10. hashes the **post-sign** executable and generated `Info.plist` bytes;
11. retains byte-identical copies of both files and re-hashes them;
12. preserves the exact signed `.app` as a transferable zip, records that exact zip digest, re-extracts it, byte-compares the executable/Info.plist to the archived originals, and strictly verifies the rehydrated signature;
13. emits the existing closed-world `NembraCaptureExternalBuildRecord.json` schema v3 using the exact signed executable/Info.plist digests;
14. reads the generated schema-v3 record back and re-hashes the retained executable/Info.plist against the record before publication;
15. emits `NembraCaptureSignedFieldCandidateEvidence.json` with the signed-app archive digest, verified code-signature team, and explicit `signed-field-candidate-not-field-authorization` evidence class;
16. optionally installs the exact archived `.app` through `devicectl` only when the caller explicitly supplies a device identifier, retaining only success/failure state rather than the device identifier.

## Output

Default output directory:

`artifacts/Xcode27FieldCandidate/`

This path is covered by the repository's existing lowercase `artifacts/` ignore rule, so a successful local field-candidate build does not silently dirty the exact checkout used for later source-admission checks.

Important retained evidence includes:

- `NembraFieldCandidate.xcarchive` — the exact local Xcode archive;
- `build-evidence/Nembra` — retained post-sign executable bytes;
- `build-evidence/Info.plist` — retained generated build metadata;
- `build-evidence/Nembra.signed-app.zip` — transferable archive of the exact signed `.app`, verified by immediate re-extraction;
- `NembraCaptureExternalBuildRecord.json` — current schema-v3 build rendezvous record;
- `NembraCaptureSignedFieldCandidateEvidence.json` — signed candidate / bundle archive evidence;
- `logs/xcodebuild-archive.log`;
- `logs/codesign-verify.log`;
- `logs/codesign-rehydrated-verify.log`;
- `logs/codesign-details.log`;
- `environment.txt` with non-secret build/evidence identifiers, the requested team, the independently read code-signature team, digests, and only a boolean/result for optional device installation.

## Why the final digest stays external

The executable SHA-256 must not be embedded in a resource inside the same final signed app whose executable it hashes. Apple code signing seals bundle resources and stores signing data in the Mach-O executable; feeding the final executable digest into the signed bundle creates a self-reference. The V14 pattern remains:

pre-build build/source/build-instance declarations -> signed build -> post-sign measurement -> external exact record/evidence -> independent acceptance.

The build-instance ID is only the rendezvous key connecting the running app declaration to the external post-build evidence. Its UUID shape does not authenticate anything by itself. Likewise, a matching code-signature team establishes only which team signed these app bytes; it is not Nembra field authorization.

## What this tooling does not prove

A successful signed candidate does **not** prove:

- that the candidate has received independent Nembra field acceptance;
- that the package physical execution gate is GO;
- that the physical runbook is GO;
- that the exact candidate was the app actually used for a later physical capture unless that later artifact/runtime provenance is correlated;
- that an optional device install was performed unless the retained environment state says it succeeded;
- physical AOVOPRO ES80 identity or RF completeness;
- GATT, Tuya, DP, battery, voltage, current, power, speed, regen, or command semantics;
- scooter command acknowledgement or any safe write authority.

No characteristic-value write path is added by this tooling.

## Required next acceptance rung

After the current final Capture software head earns exact Xcode/Simulator product acceptance, run this script on that exact surviving source head from a trusted signing Mac. Preserve the complete output. Independent acceptance must then verify at minimum:

- exact source SHA and clean-source admission before and after archive;
- expected build label/build-instance tuple;
- strict code-signature success for both archived and rehydrated signed app;
- actual code-signature TeamIdentifier matches the intended accepted signing team;
- exact post-sign executable and Info.plist digests;
- exact schema-v3 record contents and its retained-byte re-verification;
- exact signed-app archive digest;
- optional device installation success state when used, without treating a device identifier as artifact evidence;
- no in-bundle executable-digest self-reference;
- recipe/procedure identity remains `ES80-FINGERPRINT-v1` / `V14`;
- the app-visible/runtime acceptance belongs to the same final candidate lineage.

Only after that evidence is accepted should a deliberate, separately reviewed product change introduce the exact field authorization/runbook GO record. That later change must still receive its own exact-head acceptance. Do not relabel this signed-candidate tooling commit, an unsigned Simulator artifact, or an ancestor build as the final physical GO build.

**PHYSICAL EXPERIMENT ONE REMAINS DO NOT RUN / NO-GO.**
