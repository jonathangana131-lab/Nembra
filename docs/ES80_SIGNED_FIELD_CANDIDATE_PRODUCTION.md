# ES80 Signed Field Candidate Production — V14

Status: **SOFTWARE PRODUCER PROCEDURE ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

This procedure produces one exact signed iPhone Nembra Capture candidate from an exact Git commit and retains the evidence needed for later independent acceptance. It does not authorize the physical ES80 experiment.

## Required external inputs

Run `scripts/ci/xcode27_signed_field_candidate.sh` on macOS with:

- `NEMBRA_DEVELOPMENT_TEAM` — the exact 10-character Apple signing TeamIdentifier;
- `NEMBRA_EXPORT_OPTIONS_PLIST` — an existing, reviewed Xcode export-options plist;
- `NEMBRA_FIELD_DEVICE_UDID` — the intended field iPhone identifier, used only by the canonical signed-IPA inspector to verify provisioning eligibility.

Optional:

- `NEMBRA_ALLOW_PROVISIONING_UPDATES=1` if the operator deliberately permits Xcode signing-asset updates;
- `ARTIFACTS_DIR=/absolute/or/repo-relative/path` to override the unique default output directory.

The intended device identifier is verification-only input. The producer does not write it into the producer manifest, signing inspection, console summary, exported app metadata, or package field-build evidence.

## Exact-source boundary

The producer refuses a dirty invocation checkout, resolves one exact 40-hex `HEAD`, and creates a fresh detached worktree at that exact commit. Archive and export occur from that detached snapshot, not from the mutable invocation checkout.

The detached worktree must still be at the same exact commit and clean after archive/export. If Xcode or another process changes source state, candidate evidence is refused.

## Release Capture launch contract

The candidate archive receives exactly:

- `NembraCaptureBuildIdentifier = Capture Build V14-<12-char source prefix>`;
- one fresh canonical `NembraCaptureBuildInstanceID`;
- `NembraCaptureBuildCommitSHA = <exact 40-hex source commit>`;
- `NembraCaptureFieldRecipe = ES80-FINGERPRINT-v1`.

`NembraCaptureFieldRecipe` is **launch routing only**. The Release app recognizes this exact marker so a normal Home-Screen launch opens the Capture shell. The marker is build-pipeline constructible and therefore cannot grant physical authority. Package-owned field authorization remains a separate gate.

After canonical signed-IPA inspection succeeds, the producer reopens the exact retained IPA, confirms that its final signed Info.plist still contains the exact field recipe, and requires those exact raw Info.plist bytes to hash to the same `infoPlistSHA256` already committed by canonical field-build evidence.

## Export-policy provenance

The external export-options plist is copied before archive/export into:

`producer-evidence/ExportOptions.plist`

The producer:

1. validates the snapshot as a plist;
2. rejects a `teamID` that conflicts with `NEMBRA_DEVELOPMENT_TEAM`;
3. hashes the exact snapshot bytes;
4. passes the snapshot — not the mutable external original — to `xcodebuild -exportArchive`;
5. re-hashes the snapshot after export and refuses evidence if it changed.

Archive and export logs are retained under `producer-evidence/logs/` and their paths are recorded in the producer manifest.

## Output topology and atomicity

The output root is unique by default:

`artifacts/Xcode27FieldCandidate-<source-prefix>-<build-instance>/`

The producer canonicalizes the requested path, rejects `/`, the repository root, symlink/preexisting output targets, and in-repository output that is not already Git-ignored. It never mixes a new candidate into an old evidence directory.

The output intentionally has two authority domains:

### `producer-evidence/`

Owned by the producer and contains:

- exact retained `ExportOptions.plist`;
- `logs/xcodebuild-archive.log`;
- `logs/xcodebuild-export.log`;
- `field-candidate-environment.txt` with exact source/build/recipe/team identifiers and SHA-256 bindings to the canonical inspector outputs.

### `field-evidence/`

Owned exclusively by `es80_signed_field_artifact_evidence.py`.

The producer does **not** pre-create this directory. The canonical inspector stages and publishes it atomically/no-replace. It contains the retained exact IPA plus the canonical external build record, package-decodable field-build evidence record, and non-authorizing signing inspection.

This separation is deliberate: producer logs/export-policy provenance must not weaken or bypass the inspector's atomic publication contract.

## Intended-device and signing verification

The producer passes `NEMBRA_FIELD_DEVICE_UDID` directly to the current canonical inspector as `--intended-device-udid`.

The inspector is responsible for the current accepted fail-closed signed-artifact checks, including exact device platform, strict code signature, leaf-certificate authorization by the provisioning profile, effective entitlement authorization, profile expiration, and intended-device provisioning eligibility. The producer does not duplicate or weaken that authority logic.

A successful inspection allows the producer manifest to record only:

`intended_field_device_verified=yes`

It never records the UDID itself.

## macOS Bash 3.2 compatibility

The producer is written for the older `/bin/bash` available on macOS:

- no optionally empty provisioning-argument arrays under `set -u`;
- no nullglob/empty IPA arrays;
- optional `-allowProvisioningUpdates` is applied through a wrapper function;
- final IPA selection uses Python and requires exactly one regular top-level `.ipa`;
- archive/export pipeline exit statuses are captured explicitly so `tee` cannot hide Xcode failure.

## Producer evidence bindings

`producer-evidence/field-candidate-environment.txt` records SHA-256 values for:

- exact export-options snapshot;
- exact external build record;
- exact canonical field-build evidence record;
- exact signing-inspection companion;
- exact retained signed IPA.

It also records the exact source commit, build label, build instance, launch recipe, signing team, provisioning-update policy, evidence/log paths, recipe/procedure version, and `physical_authorization=not-granted`.

These are evidence references, not authorization.

## What success does not prove

A successful producer run does **not** prove:

- independent acceptance of the exact retained IPA/evidence;
- installation or Home-Screen launch on the intended iPhone;
- a configured/accepted production P-256 authorization trust root;
- package field-GO authorization;
- final runbook GO;
- physical AOVOPRO ES80 identity;
- any GATT/Tuya/DP/telemetry semantic;
- command safety or acknowledgement;
- a successful physical capture.

The private signing/authorization key must never be committed to the repository or embedded in the app. A producer result remains a **candidate** until independent acceptance and the later package/runbook authority gates are deliberately closed.

## Physical status

**DO NOT RUN PHYSICAL EXPERIMENT ONE.** The producer can create the exact signed evidence subject needed by the next acceptance rung, but it cannot authorize the scooter experiment by itself.
