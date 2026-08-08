# ES80 Signed Field Build Evidence — V14

## Purpose

The first physical ES80 capture requires one exact signed/installable iPhone build that can be correlated to the software build running Nembra. Simulator provenance is not enough.

This document describes the converged **evidence-only** path. It deliberately does not create field authorization.

## One canonical field-evidence format

The package owns the closed-world signed-installable evidence schema:

`PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON`

Schema v1 contains exactly:

- `schemaVersion = 1`;
- SHA-256 of the exact schema-v3 external build-record bytes;
- SHA-256 of the exact final signed `.ipa` bytes;
- installable kind exactly `ipa`;
- build identifier;
- build-instance ID;
- exact source commit SHA;
- exact executable SHA-256;
- exact raw root `Info.plist` SHA-256;
- recipe `ES80-FINGERPRINT-v1`;
- procedure `V14`.

Unknown fields fail closed. Authority-looking additions such as `physicalGO` or `accepted` are therefore rejected instead of being silently ignored.

The producer and consumer intentionally use this same schema. There is no separate candidate JSON that later needs to be translated into package authority vocabulary.

## Signed-device producer

`scripts/ci/xcode27_signed_field_candidate.sh` produces one Release archive/export for `generic/platform=iOS` from a pristine exact Git HEAD. It:

1. requires an explicit Apple development team and export-options plist;
2. derives `Capture Build V14-<12-char exact HEAD>`;
3. creates one fresh canonical build-instance UUID before the build;
4. injects build label, build-instance ID, and exact source SHA into the app bundle;
5. archives and exports exactly one `.ipa`;
6. passes that exact installable to `es80_field_candidate_verify.py`.

The runner never changes the package field gate or the physical runbook.

## Fail-closed IPA verification

The verifier reopens the exact exported IPA and requires:

- exactly one `Payload/<app>.app/Info.plist`;
- safe ZIP paths with no traversal or symbolic links;
- bundle identifier `com.jonathangana131.nembra`;
- device platform `iphoneos` / `iPhoneOS`, never Simulator;
- build label exactly derived from the accepted source SHA;
- canonical lowercase build-instance UUID;
- embedded source SHA exactly equal to repository HEAD;
- the declared bundle executable to exist;
- `codesign --verify --deep --strict` success;
- a non-ad-hoc signature with TeamIdentifier and CDHash;
- an embedded provisioning profile whose TeamIdentifier matches the code signature;
- a non-expired provisioning profile;
- exact `application-identifier = <TeamIdentifier>.com.jonathangana131.nembra`;
- no trusted/executable-digest/field-evidence record embedded back inside the signed app.

## Retained exact outputs

A successful run refuses to overwrite an existing evidence set and retains:

- `build-evidence/NembraField.ipa` — exact signed installable bytes;
- `build-evidence/Nembra` — exact executable bytes extracted from that IPA;
- `build-evidence/Info.plist` — exact raw root build metadata bytes;
- `build-evidence/embedded.mobileprovision` — exact provisioning-profile bytes;
- `NembraCaptureExternalBuildRecord.json` — existing closed-world schema v3;
- `NembraCaptureFieldBuildEvidenceRecord.json` — package-owned closed-world field schema v1;
- `NembraCaptureFieldSigningEvidence.json` — supporting signing/provisioning facts with explicit `signing-evidence-only-no-go` status;
- `PHYSICAL_NO_GO.txt` — explicit safety/truth boundary.

All retained binary evidence is re-hashed after write. The field record must bind the exact external-record bytes and exact retained IPA bytes.

Signing metadata stays separate from the package field-evidence schema because observed TeamIdentifier/CDHash/profile facts are evidence about the candidate, not package-owned physical authorization.

## Runtime rendezvous

`PassiveBluetoothCaptureFieldBuildEvidenceRecord.makeRuntimeBoundRendezvous(...)` requires exact equality across:

1. field-build evidence;
2. exact schema-v3 external build record;
3. `PassiveBluetoothCaptureRuntimeBuildIdentity` measured from the running application.

After the V14 runtime-Info.plist hardening, the comparison includes **both** executable SHA-256 and raw root `Info.plist` SHA-256. A detached app with the right executable but altered build metadata fails closed.

The resulting rendezvous remains software/build evidence only. It can project the existing SoftwareExport build reference but cannot mutate `PassiveBluetoothExperimentOneFieldExecutionGate`.

## Remaining independent trust rung

A locally valid signed candidate is not accepted merely because Apple code-signing checks pass or because these JSON records parse.

Before physical GO, a trusted acceptance path still must independently verify/attest the exact retained IPA, exact field-evidence bytes, exact external-record bytes, accepted signing identity/policy, final app/product acceptance, and exact installed-build correlation. Only then may a deliberate package field-gate + definitive runbook change authorize the exact accepted build.

## Physical status

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.**
