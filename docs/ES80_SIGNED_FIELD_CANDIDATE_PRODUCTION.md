# ES80 Signed Field Candidate Production — V14

Status: **CANDIDATE PRODUCTION / EVIDENCE ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

## Canonical production chain

`scripts/ci/xcode27_signed_field_candidate.sh` produces the real signed/exported iPhone Capture candidate from one fresh detached worktree at the exact source SHA. It stamps the V14 build tuple plus `NembraCaptureFieldRecipe=ES80-FINGERPRINT-v1`, exports exactly one IPA, passes that exact IPA to the canonical post-build inspector, and then rechecks the immutable retained subject and evidence relationships.

The field-recipe Info.plist value is launch routing only. It lets an accepted Release field build opened from the iPhone Home Screen enter the Capture instrument without a DEBUG-only Xcode argument. It cannot grant physical authority; the package field gate remains independently fail-closed.

The producer does not create another package field-evidence schema. The inspector-owned machine-readable subjects remain:

- `capture-evidence/NembraCaptureExternalBuildRecord.json` — schema-v3 exact executable/Info.plist/build rendezvous;
- `capture-evidence/NembraCaptureFieldBuildEvidenceRecord.json` — closed-world package field-build record binding the exact signed IPA digest;
- `capture-evidence/NembraCaptureSignedFieldArtifactInspection.json` — non-authorizing platform/signing/provisioning diagnostics;
- `capture-evidence/build-evidence/NembraField.ipa` — retained exact exported signed installable.

Producer-owned release provenance remains a sibling under `producer/`; it is never written into or appended to the inspector-owned atomic evidence directory.

## Intended field device

The current inspector requires an intended-device identifier to prove that the embedded provisioning profile authorizes the actual field target when device eligibility is applicable.

The producer therefore requires `NEMBRA_FIELD_DEVICE_UDID` as an external verification-only input. It:

1. requires a nonblank bounded token with no whitespace/control characters;
2. does not invent one fixed Apple UDID format;
3. forwards it only to `--intended-device-udid` on the canonical inspector;
4. never prints it, hashes it, writes it to producer metadata, embeds it in a path, or adds it to retained evidence.

The canonical inspector performs the actual profile eligibility check. A producer success does not prove that the IPA was installed or launched on that iPhone.

## Failure-atomic evidence topology

The inspector owns failure-atomic/no-replace publication of `capture-evidence/`, so the producer must not pre-create that path.

For every run the producer resolves one unique candidate root from source SHA plus build-instance UUID (unless the caller supplies a one-shot `ARTIFACTS_DIR`) and refuses any existing destination. Inside that root:

- `producer/` may exist before archive/export and contains producer-owned logs/policy/provenance;
- `capture-evidence/` must not exist when the inspector starts;
- the inspector stages and atomically publishes `capture-evidence/` only after its full signed-IPA checks succeed.

This prevents an export log or policy snapshot from accidentally defeating the inspector's no-replace evidence boundary.

## Exact external export policy

`NEMBRA_EXPORT_OPTIONS_PLIST` is external release input. The producer does not guess or synthesize an Xcode export method.

Before archive/export it:

1. physically canonicalizes the candidate root before safety decisions;
2. rejects `/`, repository root, or any already-existing candidate root;
3. requires any in-repository candidate root to already be Git-ignored;
4. copies the supplied export-options plist to `producer/ExportOptions.plist`;
5. validates that retained snapshot as a plist;
6. rejects a snapshot `teamID` that disagrees with `NEMBRA_DEVELOPMENT_TEAM`;
7. hashes the exact retained snapshot;
8. passes that retained snapshot — not the caller's mutable original path — to `xcodebuild -exportArchive`;
9. re-hashes it after export and fails closed if its bytes changed.

The exact producer-owned export policy and its SHA-256 are therefore reviewable without mutating inspector evidence.

## macOS Bash 3.2 portability

The producer runs under `/bin/bash` with `set -u`. The macOS system Bash can fail on optionally empty arrays.

The current producer therefore avoids those forms entirely:

- provisioning updates are a validated `0|1` input handled by explicit `run_xcodebuild` branching;
- exact exported-IPA selection is performed by Python and must find exactly one regular top-level `.ipa`;
- archive/export logs use direct redirection rather than `PIPESTATUS` arrays.

Source-contract tests reject the older optional-array/nullglob forms.

## Durable producer provenance

`producer/` retains:

- exact `ExportOptions.plist` bytes and SHA-256;
- `logs/xcodebuild-archive.log`;
- `logs/xcodebuild-export.log`;
- `field-candidate-environment.txt`, containing source SHA, build identifier, build-instance ID, field recipe, requested development team, provisioning-update setting, export-policy digest, relative log/evidence locations, procedure identity, Xcode version, and `physical_authorization=not-granted`.

The intended-device identifier is deliberately absent.

The detached source worktree is rechecked after archive/export and must still be the exact clean source SHA.

## Exact final IPA checks

The canonical inspector verifies the final IPA's iPhone platform, strict code signature, signer/profile/certificate relationship, effective signed entitlements, profile expiration/application identity, intended-device eligibility, exact executable/Info.plist/build tuple, and exact retained IPA/evidence digests.

After that inspector has successfully retained the exact IPA, the producer re-verifies the field/external/inspection digest relationships and the retained IPA SHA-256. It also reopens only that already-inspected immutable IPA to require exactly one top-level app `Info.plist` whose `NembraCaptureFieldRecipe` is exactly `ES80-FINGERPRINT-v1`.

That launch-marker check does not create physical authority. The marker is committed by the exact Info.plist SHA already bound into external/package evidence.

## What producer success does not prove

A successful run does **not** prove:

- independent Nembra acceptance of the retained IPA/evidence;
- that the export policy is the finally accepted installation route;
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
