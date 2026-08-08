# ES80 Signed Field IPA Production — V14

Status: **PRODUCER / EVIDENCE ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

## Purpose

The Capture flagship already owns one canonical signed-IPA evidence verifier: `scripts/ci/es80_signed_field_artifact_evidence.py`. It measures an already-produced iPhone IPA, verifies its device platform and code signature, retains the exact IPA, hashes the exported executable and `Info.plist`, and emits the canonical schema-v3 external build record plus `signed-field-artifact-evidence-not-field-authorization` evidence.

The remaining production gap is earlier in the chain: produce a real exported IPA from the exact accepted Capture source without inventing a second evidence schema or guessing Xcode 27 export policy.

`scripts/field/xcode27_signed_capture_ipa.sh` is that producer.

It intentionally composes:

`exact clean source -> signed iOS archive -> Xcode export -> exact IPA -> canonical flagship verifier -> retained evidence`

It does **not** compose:

`evidence -> acceptance -> field authorization -> physical GO`.

Those remain independent later gates.

## Required inputs

Run on a trusted macOS signing machine with Xcode 27 after checking out the exact Capture source commit intended to become the field candidate.

Required environment:

- `NEMBRA_DEVELOPMENT_TEAM` — exact intended 10-character Apple Developer Team ID;
- `NEMBRA_EXPORT_OPTIONS_PLIST` — path to an existing Xcode export-options plist for the intended field distribution.

The producer deliberately does not hardcode an export method such as development, ad hoc, or App Store. Xcode export vocabulary and the team's chosen provisioning path are external release inputs. The exact export-options bytes are retained and SHA-256 measured so later review can identify what was used.

If the export options contain a `teamID`, it must exactly equal `NEMBRA_DEVELOPMENT_TEAM`. A missing `teamID` is permitted because the archive itself is produced with the requested team and the **final exported IPA** is independently measured by the canonical verifier.

No certificate private key, provisioning credential, authorization private key, device identifier, or secret is written to the repository by this producer.

## Source admission and non-destructive outputs

Before any build output is created, the producer requires:

- exact lowercase 40-hex `HEAD^{commit}`;
- no tracked modifications;
- no non-ignored untracked files.

Any generated `ARTIFACTS_DIR` or `DERIVED_DATA` path located inside the repository must already be ignored by Git. The default artifact directory is unique per source/build-instance under the repository's already-ignored lowercase `artifacts/` root; default DerivedData is a unique build-instance path outside the repository.

The producer refuses an artifact or DerivedData path that already exists. It never `rm -rf`s caller-selected field-production state merely to make a rerun succeed. This keeps prior signed candidates/evidence durable and prevents a mistyped environment path from becoming a destructive cleanup target.

The producer re-runs the source cleanliness check after archive and again after export. Any new non-ignored repository state invalidates the exact-source production claim.

## Build identity

One fresh lowercase UUID build-instance rendezvous ID is generated before archive. The archive receives:

- `NembraCaptureBuildIdentifier = Capture Build V14-<first 12 source SHA characters>`;
- `NembraCaptureBuildInstanceID = <fresh UUID>`;
- `NembraCaptureBuildCommitSHA = <exact 40-hex source SHA>`.

These declarations are correlation inputs only. They are not authorization.

The final exported IPA is then passed to the existing canonical verifier, which re-reads and validates the declarations from the exported app, verifies the bundle/device platform, runs strict code-signature checks, rejects ad-hoc signing, requires a concrete `TeamIdentifier`, rejects embedded external authority records, and hashes the post-export IPA/executable/Info.plist bytes.

The producer adds one consistency check: the `TeamIdentifier` measured from the final exported IPA must equal `NEMBRA_DEVELOPMENT_TEAM`. The canonical evidence keeps the measured team value.

## Single evidence format

This producer does **not** create a parallel signed-candidate JSON schema.

Its authoritative software-evidence outputs are exactly the outputs of `scripts/ci/es80_signed_field_artifact_evidence.py`:

- `evidence/build-evidence/NembraField.ipa` — retained exact exported IPA;
- `evidence/NembraCaptureExternalBuildRecord.json` — canonical closed-world schema-v3 external build record;
- `evidence/NembraCaptureSignedFieldArtifactEvidence.json` — canonical signed-IPA evidence with explicit non-authorization authority label.

The producer independently re-hashes the retained IPA and exact external-record bytes against those canonical outputs before reporting success.

Supporting production evidence also includes:

- `NembraField.xcarchive`;
- `ExportOptions.plist` — retained exact external export settings used for this production;
- `producer-environment.txt` — source/build-instance/requested-team/export-options digest and canonical output digests;
- `logs/xcodebuild-archive.log`;
- `logs/xcodebuild-export.log`;
- `logs/canonical-field-evidence.log`.

## Why an exported IPA matters

An unsigned Simulator build cannot authorize a physical iPhone experiment. A zipped `.app` produced directly from an archive is also not the same evidence subject as the final Xcode-exported IPA that will be retained and independently accepted.

The canonical field evidence binds the exact exported IPA SHA-256 and byte count in addition to the exact post-export executable, Info.plist, source/build-instance tuple, signing team/authority chain, recipe, procedure, and exact external build-record digest.

That is the correct software subject for the later independent acceptance/authorization rung.

## What producer success does not prove

A successful run does **not** prove:

- independent Nembra acceptance of the retained IPA;
- that the retained IPA was installed on the intended iPhone;
- that the selected export policy makes the IPA appropriate for the intended installation route;
- that an independently controlled authorization key approved these bytes;
- that the package physical execution gate is GO;
- that the V14 physical runbook is GO;
- physical AOVOPRO ES80 identity;
- RF completeness;
- GATT/Tuya/DP meanings;
- battery, voltage, current, power, speed, regen, or command semantics;
- command acknowledgement or any safe characteristic write authority.

No application Bluetooth write path is added by this producer.

## Final acceptance sequence

For the first physical Experiment One, the surviving final Capture composition still requires:

1. terminal exact-head Xcode 27 app/package/UI/provenance acceptance on the final software SHA;
2. screenshot inspection plus final accessibility/performance acceptance;
3. run this producer from that exact surviving source with the intended signing/export configuration;
4. retain the complete canonical IPA evidence outputs;
5. independently verify and accept the exact retained IPA + external schema-v3 record + running executable/Info.plist subjects, including the intended installation route;
6. establish the independently controlled authorization keypair outside the repository/app and pin only the reviewed public trust root;
7. issue and verify non-forgeable authorization for that exact accepted build;
8. deliberately evolve the package field gate and physical runbook to GO for that exact build and re-run required exact-head product acceptance;
9. only then execute the stationary/passive V14 procedure and collect the first real ES80 artifact.

Until all applicable gates above are closed:

**PHYSICAL EXPERIMENT ONE / FIRST REAL ES80 CAPTURE: DO NOT RUN / NO-GO.**
