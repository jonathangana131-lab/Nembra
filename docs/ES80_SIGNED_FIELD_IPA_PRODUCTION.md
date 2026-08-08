# ES80 Signed Field IPA Production — V14

Status: **PRODUCER / EVIDENCE ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

## Purpose

The Capture flagship already owns one machine-readable signed-installable evidence contract and one canonical post-build inspector: `scripts/ci/es80_signed_field_artifact_evidence.py`.

That inspector accepts an already-produced iPhone `.ipa`, verifies its device platform and code signature, retains the exact IPA, hashes the post-export executable and raw `Info.plist`, emits the schema-v3 external build record, emits the closed-world `NembraCaptureFieldBuildEvidenceRecord.json` consumed by the package rendezvous, and keeps signing/platform diagnostics in a separate non-authorizing inspection record.

The remaining production gap is earlier in the chain: produce the actual exported IPA from the exact accepted Capture source without inventing another evidence format or guessing Xcode 27 export policy.

`scripts/field/xcode27_signed_capture_ipa.sh` closes only that production rung:

`exact clean source -> signed iOS archive -> Xcode export -> exact IPA -> canonical flagship inspector -> retained evidence`

It does **not** compose:

`evidence -> independent acceptance -> signed GO authorization -> package field GO -> physical experiment`.

## Required external inputs

Run on a trusted macOS signing machine with Xcode 27 after checking out the exact Capture commit intended to become the field candidate.

Required environment:

- `NEMBRA_DEVELOPMENT_TEAM` — exact intended 10-character Apple Developer Team ID;
- `NEMBRA_EXPORT_OPTIONS_PLIST` — path to an existing Xcode export-options plist for the intended field distribution.

The producer deliberately does not hardcode or synthesize an Xcode export `method`. Export vocabulary and the team's intended provisioning/install route are release inputs outside source code. The exact export-options bytes are retained and SHA-256 measured for later review.

If the export options contain `teamID`, it must exactly equal `NEMBRA_DEVELOPMENT_TEAM`. If they omit it, the archive still uses the requested development team and the canonical inspector measures the final exported IPA's real code-signature `TeamIdentifier`; producer success additionally requires that measured team to equal the requested team.

No certificate private key, provisioning credential, authorization private key, device identifier, or secret is created or committed by this producer.

## Exact-source and non-destructive output contract

Before producing output the script requires:

- exact lowercase 40-hex `HEAD^{commit}`;
- no tracked modifications;
- no non-ignored untracked files.

Any `ARTIFACTS_DIR` or `DERIVED_DATA` inside the repository must already be ignored by Git. Defaults are unique per build instance: an already-ignored `artifacts/Xcode27FieldIPA-<source>-<instance>/` directory plus a unique DerivedData path outside the repository.

The producer refuses an artifact or DerivedData path that already exists. It does not delete old signed candidates/evidence to make a rerun succeed, and it does not `rm -rf` a caller-selected field-production path.

Repository cleanliness is checked again after archive and after export. Any new non-ignored source state invalidates the exact-HEAD production claim.

## Build identity

One fresh lowercase UUID build-instance rendezvous ID is generated before archive. The archive receives:

- `NembraCaptureBuildIdentifier = Capture Build V14-<first 12 source SHA characters>`;
- `NembraCaptureBuildInstanceID = <fresh UUID>`;
- `NembraCaptureBuildCommitSHA = <exact 40-hex source SHA>`.

These values are correlation/provenance declarations only. They do not authorize physical execution.

The final exported IPA is passed into the canonical inspector, which must re-read and accept the embedded tuple from the exported app, require the Nembra bundle and iPhoneOS platform, reject Simulator/ad-hoc/ambiguous IPA forms, run strict code-signature verification, require concrete signing metadata, reject embedded external authority records, and hash the exact post-export bytes.

## One canonical evidence topology

The producer creates **no parallel candidate JSON schema**.

Its machine-readable field subjects are exactly the incumbent flagship outputs:

- `evidence/build-evidence/NembraField.ipa` — retained exact exported IPA;
- `evidence/NembraCaptureExternalBuildRecord.json` — closed-world external schema v3;
- `evidence/NembraCaptureFieldBuildEvidenceRecord.json` — closed-world package rendezvous record binding the exact IPA digest and exact external record/build tuple;
- `evidence/NembraCaptureSignedFieldArtifactInspection.json` — separate non-authorizing signing/platform diagnostics binding the field-build record, external record, and IPA.

After the canonical inspector returns, the producer independently checks that:

- the inspection authority remains `signed-field-artifact-inspection-not-field-authorization`;
- final measured `TeamIdentifier` equals `NEMBRA_DEVELOPMENT_TEAM`;
- retained installable kind remains exactly `ipa`;
- build identifier, build-instance ID, and source SHA agree across external record, package field-build record, and signing inspection;
- retained IPA SHA-256 equals the package field-build record and signing inspection;
- exact external-record bytes hash to the digest in both dependent records;
- exact field-build-record bytes hash to the digest in the signing inspection.

Those are producer consistency checks, not independent acceptance.

Supporting production evidence also retains:

- the `.xcarchive` used for export;
- exact `ExportOptions.plist` bytes;
- `producer-environment.txt` with source/build-instance/requested-team/export-options/canonical-output digests;
- archive/export/canonical-inspector logs.

## Why the exported IPA is the subject

An unsigned Simulator executable cannot become a physical field artifact. A directly zipped archive `.app` is also not the same evidence subject as the final Xcode-exported IPA that will actually be retained and accepted.

The canonical package field-build record binds the exact exported IPA digest as `signedInstallableSHA256` and `signedInstallableKind = ipa`, while the external record/running-app rendezvous binds exact executable + raw Info.plist identity. Signing/platform data stays in the separate inspection record so there is only one closed-world package evidence schema.

## What producer success still does not prove

A successful run does **not** prove:

- independent Nembra acceptance of the retained IPA or records;
- that the selected export policy is the accepted installation route;
- that the retained IPA was successfully installed on the intended field iPhone;
- that an independently controlled authorization key approved the exact retained subjects;
- that the production public trust root has been deliberately configured;
- that the package physical execution gate is GO;
- that the V14 physical runbook is GO;
- physical AOVOPRO ES80 identity or RF completeness;
- GATT/Tuya/DP, battery, voltage, current, power, speed, regen, or command semantics;
- command acknowledgement or safe write authority.

No application Bluetooth characteristic-value write path is added.

## Remaining field acceptance sequence

For the first physical Experiment One, the surviving final Capture composition still requires:

1. terminal exact-head Xcode 27 package/app/UI/provenance acceptance on the final software SHA;
2. actual screenshot inspection plus final accessibility/performance acceptance;
3. run this producer on that exact surviving source with the intended signing/export configuration;
4. preserve the complete canonical IPA/evidence output;
5. independently accept the exact retained IPA + exact field-build record + exact schema-v3 external record + exact running executable/Info.plist rendezvous, including the intended installation route;
6. establish the independently controlled authorization keypair outside the repository/app and pin only the reviewed public trust root;
7. issue and verify non-forgeable authorization for the exact accepted subjects;
8. only then deliberately evolve/consume that verified authority in the package field gate and record final runbook GO for the exact build, with required exact-head acceptance after that composition;
9. only after all of those gates pass execute the stationary/passive V14 procedure and collect the first real ES80 artifact.

Until then:

**PHYSICAL EXPERIMENT ONE / FIRST REAL ES80 CAPTURE: DO NOT RUN / NO-GO.**
