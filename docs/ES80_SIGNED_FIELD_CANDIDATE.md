# ES80 Signed Field Candidate — V14

Status: **SIGNED-CANDIDATE TOOLING ONLY / PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

## Purpose

The current Capture flagship can produce exact Simulator provenance, but Simulator bytes cannot authorize a physical ES80 experiment. `scripts/field/xcode27_signed_capture_candidate.sh` closes the next mechanical gap: on a trusted local Mac with Xcode 27 and a configured Apple Developer signing identity, it produces one exact signed iOS Capture candidate and preserves post-sign evidence without feeding the final executable digest back into the signed app bundle.

`scripts/field/verify_signed_capture_candidate.py` is the path-disjoint portable consumer. It independently re-checks record shape, hashes, embedded build declarations, and the transferable signed-app archive against the retained evidence. Its success means **self-consistent byte provenance only**. It does not authenticate who produced the records, re-run Apple code-signature verification, accept the product, or authorize a physical experiment.

Neither script is a GO button. A successful archive, valid code signature, successful optional device installation, matching schema-v3 record, exact digest, or portable verifier success still requires independent product acceptance before the package field gate/runbook may be evolved to GO.

## Relationship to the V14 field-authorization verifier

The accepted Capture lineage contains `PassiveBluetoothExperimentOneFieldAuthorizationVerifier`, which consumes a separately signed, closed-world authorization envelope and requires exact equality with the accepted build tuple. Its production trust root is intentionally unconfigured until a deliberate independent authority is established.

The tooling in this document does **not** create an authorization envelope, choose or configure that trust root, sign an authorization decision, or mutate the package field gate. It produces and checks the exact signed-build evidence that a later independent authority would need before it could legitimately authorize one field build.

The evidence order remains:

signed candidate -> exact post-sign evidence -> independent acceptance/trust decision -> valid authorization envelope -> final composed exact-head GO gate/runbook.

Skipping any rung is forbidden.

## Required local inputs

Run only from the exact clean Capture candidate checkout intended for review.

Required for signed-candidate production:

- macOS with Xcode 27 selected;
- an Apple Developer account/signing identity already usable by Xcode;
- `NEMBRA_DEVELOPMENT_TEAM` set to the exact 10-character Apple Developer Team ID;
- a completely clean Git worktree, including no non-ignored untracked files.

Optional:

- `NEMBRA_INSTALL_DEVICE_ID` may name one `devicectl` device identifier. If supplied, the producer attempts to install the exact archived signed `.app` after all evidence checks. Installation success is only installability evidence; it does not open the physical Capture field gate. The device identifier and raw `devicectl` output are not retained in the evidence bundle.

The producer does not request, print, commit, or manufacture signing certificates/private keys/provisioning secrets.

Example invocation from the repository root after selecting the exact intended source head:

```bash
NEMBRA_DEVELOPMENT_TEAM=ABCDEFGHIJ \
  bash scripts/field/xcode27_signed_capture_candidate.sh
```

Optional exact-device installability check:

```bash
NEMBRA_DEVELOPMENT_TEAM=ABCDEFGHIJ \
NEMBRA_INSTALL_DEVICE_ID='<devicectl device identifier>' \
  bash scripts/field/xcode27_signed_capture_candidate.sh
```

Do not commit either local value into the repository.

## Exact production sequence

The producer:

1. resolves exact `HEAD^{commit}` and requires one lowercase 40-hex commit;
2. rejects tracked changes and all non-ignored untracked files before writing output;
3. generates the human-readable V14 build label and one fresh lowercase UUID build-instance rendezvous ID before the build;
4. archives `Nembra` for generic iOS Release with automatic signing under the explicitly supplied development team;
5. injects `NembraCaptureBuildIdentifier`, `NembraCaptureBuildInstanceID`, and `NembraCaptureBuildCommitSHA` through generated Info.plist settings;
6. re-reads the final archived signed app and requires exact equality for all three declarations plus the expected bundle identifier;
7. rejects any executable-digest provenance record found inside the app bundle;
8. runs strict `codesign` verification on the archived app and retains signature details;
9. hashes the **post-sign** executable and generated `Info.plist` bytes;
10. retains byte-identical copies of both files and re-hashes them;
11. preserves the exact signed `.app` as a transferable zip, records that exact zip digest, re-extracts it, byte-compares the executable/Info.plist to the archived originals, and strictly verifies the rehydrated signature;
12. emits the existing closed-world `NembraCaptureExternalBuildRecord.json` schema v3 using the exact signed executable/Info.plist digests;
13. emits `NembraCaptureSignedFieldCandidateEvidence.json` with the signed-app archive digest and explicit `signed-field-candidate-not-field-authorization` evidence class;
14. optionally installs the exact archived `.app` through `devicectl` only when the caller explicitly supplies a device identifier, retaining only success/failure state rather than the device identifier.

## Output

Default output directory:

`Artifacts/Xcode27FieldCandidate/`

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
- `environment.txt` with non-secret build/evidence identifiers, digests, and only a boolean/result for optional device installation.

## Portable self-consistency verification

The evidence directory can be checked on a separate machine without signing credentials:

```bash
python3 scripts/field/verify_signed_capture_candidate.py \
  Artifacts/Xcode27FieldCandidate
```

The verifier fails closed on:

- unknown or missing fields in either evidence record;
- noncanonical build-instance, Git SHA, digest, team, recipe, or procedure values;
- disagreement between the schema-v3 external record and signed-field evidence tuple;
- retained executable or Info.plist hash mismatch;
- embedded Info.plist build/source/build-instance mismatch;
- signed-app zip digest mismatch;
- zip executable/Info.plist bytes diverging from retained evidence;
- duplicate required zip members or parent-directory traversal entries.

A successful portable result is deliberately labeled:

- `verification = self-consistent-byte-provenance`;
- `authenticity = not-established-by-portable-verifier`;
- `codeSignatureVerification = not-reperformed-by-portable-verifier`;
- `fieldAuthorization = NO-GO`.

Actual Apple code-signature validity remains the producer's macOS `codesign` evidence and must be included in later independent acceptance. Authenticity of the evidence bundle itself also requires a trusted distribution/attestation decision; matching local JSON is not a trust anchor.

## Why the final digest stays external

The executable SHA-256 must not be embedded in a resource inside the same final signed app whose executable it hashes. Apple code signing seals bundle resources and stores signing data in the Mach-O executable; feeding the final executable digest into the signed bundle creates a self-reference. The V14 pattern remains:

pre-build build/source/build-instance declarations -> signed build -> post-sign measurement -> external exact record/evidence -> independent acceptance.

The build-instance ID is only the rendezvous key connecting the running app declaration to the external post-build evidence. Its UUID shape does not authenticate anything by itself.

## What this tooling does not prove

A successful signed candidate or portable verification does **not** prove:

- that the candidate/evidence bundle is authentic merely because it is internally self-consistent;
- that the candidate has received independent Nembra field acceptance;
- that a field-authorization trust root is configured or trustworthy;
- that an accepted authorization envelope exists for this exact tuple;
- that the package physical execution gate is GO;
- that the physical runbook is GO;
- that the exact candidate was the app actually used for a later physical capture unless that later artifact/runtime provenance is correlated;
- physical AOVOPRO ES80 identity or RF completeness;
- GATT, Tuya, DP, battery, voltage, current, power, speed, regen, or command semantics;
- scooter command acknowledgement or any safe write authority.

No characteristic-value write path is added by this tooling.

## Required next acceptance rung

After the current final Capture software head earns exact Xcode/Simulator product acceptance, run the producer on that exact surviving source head from a trusted signing Mac. Preserve the complete output. Independent acceptance must then verify at minimum:

- exact source SHA and clean-source admission;
- expected build label/build-instance tuple;
- strict code-signature success for both archived and rehydrated signed app;
- exact post-sign executable and Info.plist digests;
- exact schema-v3 record contents;
- exact signed-app archive digest;
- portable self-consistency verification;
- authenticity/trust of the evidence source by a separately accepted mechanism;
- optional device installation success state when used, without treating a device identifier as artifact evidence;
- no in-bundle executable-digest self-reference;
- recipe/procedure identity remains `ES80-FINGERPRINT-v1` / `V14`;
- the app-visible/runtime acceptance belongs to the same final candidate lineage.

Only after that evidence is accepted may an independent authority issue the exact signed authorization envelope expected by `PassiveBluetoothExperimentOneFieldAuthorizationVerifier`. Only after that envelope verifies against the deliberately configured accepted trust root should a separately reviewed product change introduce the exact field authorization/runbook GO record. That final composition must still receive its own exact-head acceptance.

Do not relabel this signed-candidate tooling commit, an unsigned Simulator artifact, a self-consistent but unauthenticated record bundle, an authorization consumer with no configured trust root, or an ancestor build as the final physical GO build.

**PHYSICAL EXPERIMENT ONE REMAINS DO NOT RUN / NO-GO.**
