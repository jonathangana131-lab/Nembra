# ES80 Signed Field Candidate Production — V14

Status: **CANDIDATE PRODUCTION / EVIDENCE ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

## Canonical production chain

`scripts/ci/xcode27_signed_field_candidate.sh` produces the real signed/exported iPhone Capture candidate. It builds from a fresh detached worktree at the exact source SHA, stamps the exact V14 Capture build tuple plus `NembraCaptureFieldRecipe=ES80-FINGERPRINT-v1`, exports exactly one IPA, and passes that IPA into the canonical post-build inspector `scripts/ci/es80_signed_field_artifact_evidence.py`.

The field-recipe Info.plist value is launch routing only. It lets an accepted Release field build opened from the iPhone Home Screen enter the Capture instrument without a DEBUG-only launch argument. It cannot grant physical authority; the package field gate remains independently fail-closed.

The producer does not create another field-evidence schema. The canonical inspector owns a previously nonexistent `inspection/` child directory and publishes that evidence directory failure-atomically/no-replace. Inside it the machine-readable subjects remain:

- `inspection/NembraCaptureExternalBuildRecord.json` — schema-v3 exact executable/Info.plist/build rendezvous;
- `inspection/NembraCaptureFieldBuildEvidenceRecord.json` — closed-world package field-build record binding the exact signed IPA digest;
- `inspection/NembraCaptureSignedFieldArtifactInspection.json` — non-authorizing platform/signing/provisioning diagnostics;
- `inspection/build-evidence/NembraField.ipa` — retained exact exported signed installable.

Producer-owned export policy, Xcode logs, and `field-candidate-environment.txt` live outside that inspector-owned child. A partial producer run therefore cannot create a partial directory that masquerades as canonical signed-field evidence.

## Required external inputs

The current producer requires:

- `NEMBRA_DEVELOPMENT_TEAM` — canonical 10-character Apple TeamIdentifier;
- `NEMBRA_EXPORT_OPTIONS_PLIST` — an existing valid Xcode export-options plist;
- `NEMBRA_INTENDED_FIELD_DEVICE_UDID` — one bounded, nonblank intended field-device identifier used only for provisioning/installability verification;
- optional `NEMBRA_ALLOW_PROVISIONING_UPDATES=0|1`.

The intended-device identifier is verification-only input. The producer forwards it only to the canonical inspector's `--intended-device-udid` boundary. It must not be echoed, persisted, hashed into evidence, placed into output paths, or copied into the retained candidate records.

## Exact external export policy

`NEMBRA_EXPORT_OPTIONS_PLIST` is an external release input. The producer deliberately does not guess or synthesize an Xcode export method.

Before archive/export it:

1. resolves a unique candidate directory for the exact source/build instance;
2. physically canonicalizes that path before safety decisions so lexical `..` or existing symlink ancestors cannot bypass root checks;
3. refuses `/`, the repository root, or any already-existing candidate directory;
4. requires an in-repository candidate directory to already be Git-ignored;
5. creates producer-owned logs/provenance while deliberately leaving `inspection/` absent;
6. copies the supplied export-options plist into the producer-owned candidate area as `ExportOptions.plist`;
7. validates that retained snapshot as a plist;
8. rejects a snapshot `teamID` that disagrees with `NEMBRA_DEVELOPMENT_TEAM`;
9. hashes the exact retained snapshot;
10. passes that exact snapshot — not the caller's mutable original path — to `xcodebuild -exportArchive`;
11. re-hashes it after export and fails closed if its bytes changed.

This makes the actual export policy used for the retained IPA reviewable evidence rather than operator recollection or a mutable external path.

## macOS field-machine portability

The producer runs under `/bin/bash` with `set -u`. macOS still ships an older Bash where optionally empty arrays can fail as unbound variables.

Two optional-array hazards are intentionally absent:

- provisioning updates are a validated `0|1` input consumed by an explicit `run_xcodebuild` branch; there is no optionally empty `PROVISIONING_ARGS` array;
- exact exported-IPA selection is performed by Python and must find exactly one regular top-level `.ipa`; there is no nullglob/empty `IPA_FILES` array.

The source-contract tests explicitly reject the older array forms.

## Durable producer evidence

The candidate root retains producer-owned provenance outside `inspection/`:

- exact `ExportOptions.plist` bytes and SHA-256;
- `logs/xcodebuild-archive.log`;
- `logs/xcodebuild-export.log`;
- `field-candidate-environment.txt`, including source SHA, build identifier, build-instance ID, requested team, provisioning-update setting, field-launch recipe, export-options digest, recipe/procedure, log paths, `inspection_directory=inspection`, and `physical_authorization=not-granted`.

The archive/export commands fail if either Xcode or log capture fails. The detached source worktree is rechecked after archive/export and must still be the exact clean source SHA.

## Canonical signed-IPA inspection

The final exported IPA is passed to the current canonical inspector with:

- the exact expected source SHA;
- the verification-only intended-device identifier;
- the previously nonexistent `inspection/` output path.

The inspector is the authority for signed-artifact evidence mechanics. Current checks include:

- one unambiguous physical-iPhone IPA namespace with duplicate/traversal/symlink and component-wise Unicode/casefold alias rejection;
- iPhoneOS rather than Simulator platform;
- strict code-signature inspection;
- exact team/application identity relationship;
- embedded provisioning-profile integrity and expiry;
- actual leaf signing-certificate membership in profile `DeveloperCertificates`;
- effective signed-entitlement authorization by the embedded profile;
- intended-device eligibility through `ProvisionedDevices`, unless the accepted profile explicitly provisions all devices;
- exact retained IPA, executable, raw Info.plist, external-record, and field-record digests;
- failure-atomic/no-replace evidence publication.

The intended-device identifier is used for the eligibility comparison but is not retained in inspector evidence.

## Launch-recipe proof on the exact retained IPA

The current canonical inspector intentionally does not promote the Capture launch-routing marker into physical authority. After the inspector succeeds, the producer re-opens the **exact retained IPA** only to prove the routing marker that the installed Release app requires.

The producer:

1. finds exactly one top-level signed app `Info.plist` in the retained IPA;
2. reads those exact raw plist bytes;
3. requires `NembraCaptureFieldRecipe == ES80-FINGERPRINT-v1`;
4. hashes those same raw plist bytes;
5. requires that hash to equal the canonical field-build record's `infoPlistSHA256`.

This proves the Home-Screen Capture routing marker on the exact Info.plist bytes already bound into the signed candidate evidence. It still does not grant physical Experiment One authority.

## Post-inspector coherence checks

Before producer success is reported, the wrapper also verifies current closed-world field/inspection vocabulary and cross-record relationships, including:

- source SHA, build identifier, build-instance ID, recipe and procedure agree;
- signed-installable kind is IPA;
- non-authorizing inspection label remains exact;
- team, bundle identifier and iPhone platform remain exact;
- provisioning application identifier matches the requested Nembra app/team;
- provisioning profile digest, UUID and normalized expiration are present;
- external-record digest matches exact external-record bytes;
- field-record digest matches exact field-record bytes;
- inspection and field record agree on exact IPA, executable and raw Info.plist digests;
- retained IPA bytes hash to the canonical field record's signed-installable digest.

These checks are evidence consistency, not independent acceptance.

## What producer success does not prove

A successful run does **not** prove:

- independent Nembra acceptance of the retained IPA/evidence;
- that the selected export policy is the accepted field installation route;
- that the retained IPA was installed, launched, or runtime-matched on the intended iPhone;
- that an independently controlled authorization key approved these exact subjects;
- that the production public trust root is configured;
- that the package physical execution gate is GO;
- that the V14 physical runbook is GO;
- physical AOVOPRO ES80 identity or RF completeness;
- GATT/Tuya/DP, battery, voltage, current, power, speed, regen, or command semantics;
- command acknowledgement or safe characteristic-write authority.

No application Bluetooth characteristic-value write path is added by this producer.

## Remaining physical gate

The surviving final Capture software composition still requires terminal exact-head Apple acceptance plus real screenshot/accessibility/performance review. That exact source must then produce the signed IPA through this chain. The exact retained IPA and evidence subjects require independent acceptance. Only an independently controlled authorization key over the exact accepted subjects may then be consumed by the package-owned field gate, followed by a deliberate final runbook GO and fresh exact-head product acceptance.

Until every applicable gate is closed:

**PHYSICAL EXPERIMENT ONE / FIRST REAL ES80 CAPTURE: DO NOT RUN / NO-GO.**
