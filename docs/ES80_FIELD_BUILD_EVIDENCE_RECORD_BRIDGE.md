# ES80 Field Build Evidence Record Bridge — V14

## Purpose

The signed-field Capture provenance stack has two deliberately different external records:

1. `NembraCaptureSignedFieldArtifactEvidence.json` is the rich inspection result emitted by `es80_signed_field_artifact_evidence.py`. It records the exact IPA digest/byte count, iPhone platform declaration, observed signing TeamIdentifier/authority chain, the exact build tuple, and an explicit `signed-field-artifact-evidence-not-field-authorization` label.
2. `PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON` consumes a smaller closed-world schema-v1 rendezvous record inside the package. It intentionally rejects extra authority-looking or inspection-only fields.

Those contracts must not be treated as interchangeable. `scripts/ci/es80_field_build_evidence_record_bridge.py` is the explicit fail-closed bridge between them.

The bridge does **not** grant physical Experiment One authority.

## Inputs

Run it only after the signed-IPA inspector has successfully produced and retained its evidence:

```sh
python3 scripts/ci/es80_field_build_evidence_record_bridge.py \
  --external-record /absolute/path/NembraCaptureExternalBuildRecord.json \
  --inspection-record /absolute/path/NembraCaptureSignedFieldArtifactEvidence.json \
  --retained-ipa /absolute/path/build-evidence/NembraField.ipa \
  --output /absolute/path/NembraCaptureFieldBuildEvidenceRecord.json
```

The bridge reads the exact bytes of the schema-v3 external build record, the richer signed-artifact inspection JSON, and the exact retained IPA.

## Fail-closed binding

Before producing the package-facing wire record, it requires:

- the external build record to have exactly the supported schema-v3 key set;
- the inspection record to have exactly the current signed-artifact schema-v1 key set;
- recipe `ES80-FINGERPRINT-v1` and procedure `V14` in both records;
- the inspection authority label to remain exactly `signed-field-artifact-evidence-not-field-authorization`;
- bundle id `com.jonathangana131.nembra` and device platform `iphoneos` / `iPhoneOS` in inspection evidence;
- a concrete observed TeamIdentifier and non-empty signing authority chain in inspection evidence;
- canonical build identifier, build-instance UUID, source commit, executable SHA-256, and Info.plist SHA-256;
- exact equality of that build tuple between the external record and inspection evidence;
- `externalBuildRecordSHA256` in inspection evidence to equal SHA-256 of the exact external-record bytes passed to the bridge;
- the retained IPA byte count and SHA-256 to exactly equal the inspection evidence.

Unknown fields fail closed. A detached external record, detached retained IPA, tuple mismatch, malformed digest, or authority-looking extra field cannot produce the package-facing record.

## Exact package-facing wire record

The output contains exactly the fields accepted by `PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON`:

```text
schemaVersion
externalBuildRecordSHA256
signedInstallableSHA256
signedInstallableKind
buildIdentifier
buildInstanceID
sourceCommitSHA
executableSHA256
infoPlistSHA256
experimentRecipeID
procedureVersion
```

For V14, `schemaVersion` is `1`, `signedInstallableKind` is exactly `ipa`, `signedInstallableSHA256` is SHA-256 of the retained exact IPA bytes, `experimentRecipeID` is `ES80-FINGERPRINT-v1`, and `procedureVersion` is `V14`.

The bridge refuses to overwrite an existing output and verifies the exact bytes it writes.

## Why the records stay separate

The rich inspection record contains useful signing/platform diagnostics that should remain available for external review. The package-facing parser intentionally has a smaller closed-world surface so those diagnostics cannot accidentally become caller-constructible authorization vocabulary.

Keeping the two records separate preserves both goals: rich external evidence and a narrow deterministic package rendezvous.

## Remaining trust boundary

A successful bridge proves only deterministic equality between already-produced software/build evidence sources. It does **not** prove:

- that the observed signing team/certificate is an accepted Nembra release authority;
- that GitHub or another independent trusted service attested the exact IPA or record bytes;
- that those exact IPA bytes were installed on the field iPhone;
- that the running app is the independently accepted installable until runtime rendezvous also succeeds;
- that the package-owned Experiment One field gate is GO;
- physical AOVOPRO ES80 identity, RF completeness, GATT/Tuya/DP semantics, telemetry semantics, command acknowledgement, or safe write authority.

`PassiveBluetoothCaptureRuntimeBuildIdentity` now measures both the installed executable and raw Info.plist. When the package field-build rendezvous is composed with this bridge, it must compare **both** runtime digests, not only the executable digest.

## Development self-test

```sh
python3 scripts/ci/es80_field_build_evidence_record_bridge.py --self-test
```

The self-test covers the exact package-facing key set, `ipa` mapping, Info.plist preservation, exact external-record byte binding, unexpected authority-field rejection, and detached retained-IPA rejection.

Self-test success is development evidence only.

## Physical status

**PHYSICAL EXPERIMENT ONE / FIRST REAL ES80 CAPTURE REMAINS NO-GO / DO NOT RUN.**
