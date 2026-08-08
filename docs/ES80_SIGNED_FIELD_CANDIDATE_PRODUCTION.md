# ES80 Signed Field Candidate Production — V14

Status: **CANDIDATE PRODUCTION / EVIDENCE ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

## Canonical production chain

`scripts/ci/xcode27_signed_field_candidate.sh` produces the real signed/exported iPhone Capture candidate. It builds from a fresh detached worktree at the exact source SHA, stamps the exact V14 Capture build tuple plus `NembraCaptureFieldRecipe=ES80-FINGERPRINT-v1`, exports one IPA, and passes that IPA into the canonical post-build inspector `scripts/ci/es80_signed_field_artifact_evidence.py`.

The field-recipe Info.plist value is launch routing only. It lets an accepted Release field build opened from the iPhone Home Screen enter the Capture instrument without a DEBUG-only Xcode launch argument. It cannot grant physical authority; the package field gate remains independently fail-closed.

The producer does not create another field evidence schema. The machine-readable inspector subjects live under the producer candidate's fresh `inspection/` child:

- `inspection/NembraCaptureExternalBuildRecord.json` — schema-v3 exact executable/Info.plist/build rendezvous;
- `inspection/NembraCaptureFieldBuildEvidenceRecord.json` — closed-world package field-build record binding the exact signed IPA digest;
- `inspection/NembraCaptureSignedFieldArtifactInspection.json` — non-authorizing platform/signing/provisioning diagnostics;
- `inspection/build-evidence/NembraField.ipa` — retained exact exported signed installable.

The outer candidate directory is producer-owned provenance. Keeping that directory separate from `inspection/` is intentional: the canonical inspector publishes its evidence failure-atomically and refuses an already-existing output directory.

## Exact external export policy

`NEMBRA_EXPORT_OPTIONS_PLIST` is an external release input. The producer deliberately does not guess or synthesize an Xcode export method.

Before archive/export it:

1. resolves a unique outer candidate directory for the exact source/build-instance;
2. physically canonicalizes that path before safety decisions so lexical `..` or existing symlink ancestors cannot bypass root checks;
3. refuses `/`, the repository root, or any already-existing candidate directory;
4. requires an in-repository candidate directory to already be Git-ignored;
5. reserves a fresh, nonexistent `inspection/` child for the canonical inspector;
6. copies the supplied export-options plist into the outer candidate directory as `ExportOptions.plist`;
7. validates that retained snapshot as a plist;
8. rejects a snapshot `teamID` that disagrees with `NEMBRA_DEVELOPMENT_TEAM`;
9. hashes the exact retained snapshot;
10. passes that exact snapshot — not the caller's mutable original path — to `xcodebuild -exportArchive`;
11. re-hashes it after export and fails closed if its bytes changed.

This makes the actual export policy used for the retained IPA reviewable evidence rather than operator recollection or a mutable external path.

## Intended-device input

`NEMBRA_FIELD_DEVICE_UDID` is required only at the verification boundary. The producer forwards it directly to the canonical inspector as `--intended-device-udid` and does not echo, persist, hash, embed, or reuse it elsewhere.

The inspector is responsible for validating that verification-only input and proving that the embedded provisioning profile authorizes the intended device. The raw UDID is not part of candidate evidence.

## macOS field-machine portability

The producer runs under `/bin/bash` with `set -u`. macOS still ships an older Bash where optional empty arrays can fail as unbound variables.

Two optional-array hazards are therefore intentionally absent:

- provisioning updates are a validated `0|1` input consumed by an explicit `run_xcodebuild` branch; there is no optionally empty `PROVISIONING_ARGS` array;
- exact exported-IPA selection is performed by Python and must find exactly one regular top-level `.ipa`; there is no nullglob/empty `IPA_FILES` array.

Archive/export pipeline status is captured explicitly so failure from either Xcode or `tee` is a producer failure.

## Durable production evidence

The outer candidate directory retains:

- exact `ExportOptions.plist` bytes and SHA-256;
- `logs/xcodebuild-archive.log`;
- `logs/xcodebuild-export.log`;
- the fresh `inspection/` directory containing the canonical inspector subjects listed above;
- `field-candidate-environment.txt`, including source SHA, build identifier, build-instance ID, requested/verified team, provisioning-update setting, field-launch recipe, export-options digest, recipe/procedure, log paths, `inspection_directory=inspection`, and `physical_authorization=not-granted`.

The detached source worktree is rechecked after archive/export and must still be the exact clean source SHA.

## Signed-device checks inherited from the canonical inspector

The final exported IPA must satisfy the current canonical field-artifact inspector, including iPhoneOS rather than Simulator platform, strict code signing, profile-authorized leaf certificate, effective signed entitlements permitted by the profile, matching team/application identity, unexpired embedded provisioning profile, authorization of the verification-only intended device, and exact retained IPA/executable/Info.plist digests.

Those facts remain evidence. They do not decide that the candidate was independently accepted, installed on the intended field iPhone, or authorized for Experiment One.

## Exact Release launch-recipe proof

The current inspector binds the exact raw signed Info.plist bytes by SHA-256 but does not expose a separate launch-recipe authority field. After the inspector has safely rejected ambiguous archive members and published the retained IPA, the producer reopens that exact retained IPA and requires:

- exactly one top-level `Payload/*.app/Info.plist`;
- `NembraCaptureFieldRecipe == ES80-FINGERPRINT-v1`;
- SHA-256 of those exact raw Info.plist bytes equals the canonical field-build evidence `infoPlistSHA256`.

This proves that the exact signed candidate can take the Release Home-Screen Capture route already implemented by the app. It does **not** make the routing marker physical authority or add another evidence schema.

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

The surviving final Capture software composition still requires terminal exact-head Apple acceptance plus real screenshot/accessibility/performance review. That exact source must then produce the signed IPA through this chain. The exact retained IPA and evidence subjects require independent acceptance. Only an independently controlled authorization key over the exact accepted subjects may then be consumed by the package-owned field gate, followed by a deliberate final runbook GO and fresh exact-head product acceptance.

Until every applicable gate is closed:

**PHYSICAL EXPERIMENT ONE / FIRST REAL ES80 CAPTURE: DO NOT RUN / NO-GO.**
