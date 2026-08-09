# ES80 TODAY Final GO — Mechanical Handoff

Status: **NO-GO until the verifier emits one retained Final GO record for the exact accepted candidate.**

This document is the operator handoff for `scripts/ci/es80_today_final_go_record.py`.
It does not replace `docs/ES80_TODAY_PRIVATE_FIELD_RUNBOOK.md` or
`docs/ES80_TODAY_EXACT_RETAINED_IPA_INSTALL.md`. It makes the final transition between those
accepted evidence subjects mechanical instead of asking an operator to assemble a GO tuple from
memory or prose.

The verifier is external to the frozen/signed application lineage. Running it does not modify the
accepted app, sign an IPA, install an IPA, contact the scooter, create Bluetooth evidence, or grant
any write/command authority.

## Truth boundary

The Final GO verifier consumes two different classes of input and keeps them separate.

### Machine-verifiable subjects

The verifier independently checks:

- the live GitHub `Xcode 27 PR Exact-Head QA` run, exact source SHA, same-repository PR subject,
  terminal success, and the exact `Build, test, and capture exact PR head` job on `xcode-27`;
- the required exact-head Mac job steps, including retained Simulator capture/provenance checks and
  final stale-head rejection;
- the exact retained GitHub Actions artifact name, run binding, server-declared SHA-256, downloaded
  ZIP SHA-256, and embedded closed-world v3 `NembraCaptureExternalBuildRecord.json`;
- the retained signed IPA, external build record, field-build evidence record, signed-artifact
  inspection record, physical `iphoneos` platform, code signing/provisioning identity, unexpired
  profile, executable hash, Info.plist hash, and exact IPA hash;
- the pinned independent retained-candidate receipt, which must remain `PASS_NOT_FINAL_GO` with
  `physicalExperimentAuthorization=not-granted`;
- the accepted Research compile tuple
  `private-today-v1 / canonical-producer-explicit-mode / NEMBRA_ES80_TODAY_RESEARCH`;
- the frozen exact-source private-runner / canonical-inspector Git blobs;
- the pinned independent verifier commit
  `d827a296048386bda62024ea3278775d5344c47c` and verifier Git blob
  `c3b2b620280484c05316fc5c2fa2ca451f1fdc83`.

Do not replace any of those subjects with a screenshot, copied PR text, a Boolean switch, or a
manually typed claim.

### Human-observed procedure state

Some required facts are not machine telemetry. They are supplied in one retained JSON document with
this exact authority string:

`operator-field-attestation-not-machine-evidence`

The Final GO record hashes that document and classifies it as human-observed procedure state. The
attestation does **not** prove physical scooter identity, charger electronics, stationarity from a
sensor, BLE protocol semantics, telemetry fields, or command acknowledgement.

## Create the operator attestation

Create this JSON only after the exact retained IPA installation/rendezvous procedure is complete and
the final preflight observations are actually true. Do not pre-fill `DISCONNECTED`, `STATIONARY`,
`READY`, ResearchAdmission, or coordinator permission before observing them.

The schema is closed-world. Use exactly these keys and values, replacing only the bracketed evidence
subjects:

```json
{
  "schemaVersion": 1,
  "authority": "operator-field-attestation-not-machine-evidence",
  "attestationID": "<new-lowercase-uuid>",
  "recordedAtUTC": "<YYYY-MM-DDTHH:MM:SSZ>",
  "simulatorArtifactReview": "INSPECTED_NO_TODAY_BLOCKER",
  "installationRoute": "exact-retained-ipa-via-xcode-device-management",
  "preInstallRetainedIPASHA256": "<64-lowercase-hex>",
  "postInstallRetainedIPASHA256": "<same-64-lowercase-hex>",
  "installedWithoutRebuildOrSubstitution": true,
  "installedOnIntendedDevice": true,
  "observedDevice": "iPhone 12",
  "observedOS": "iOS 27",
  "runtimeVisibleSourceCommitSHA": "<40-lowercase-hex>",
  "runtimeVisibleBuildIdentifier": "Capture Build V14-<first-12-source-hex>",
  "runtimeVisibleBuildInstanceID": "<runtime-visible-lowercase-uuid>",
  "runtimeVisibleRecipe": "ES80-FINGERPRINT-v1",
  "runtimeResearchAdmission": "OBSERVED_AVAILABLE",
  "canonicalCoordinatorPermission": "OBSERVED_PERMITTED",
  "ordinaryGeneralBuildAuthority": "OBSERVED_NO_GO",
  "preflightHealth": "OBSERVED_READY",
  "chargerState": "DISCONNECTED",
  "motionState": "STATIONARY",
  "explicitOperatorActionRequired": true,
  "noApplicationWriteAuthorityReview": "REVIEWED_NO_APPLICATION_WRITE_OR_COMMAND_PATH"
}
```

Freshness is fail-closed. At Final GO generation time, `recordedAtUTC` must be no more than 30 minutes
old and may not be more than 5 minutes in the future. If installation/runtime/preflight state changes,
do not reuse an old attestation; produce a new observation record after the accepted state is restored.

Do not put a private device UDID, signing secret, GitHub token, password, or other credential in this
attestation or in the public repository.

## Run the Final GO verifier

Use the exact retained subjects from the same accepted candidate:

```sh
python3 scripts/ci/es80_today_final_go_record.py \
  --candidate-root /absolute/path/to/retained-candidate-root \
  --expected-source-sha <accepted-40-hex-source-sha> \
  --expected-pr-number 833 \
  --trusted-xcode-run-id <accepted-run-id> \
  --trusted-xcode-job-id <accepted-mac-job-id> \
  --trusted-xcode-artifact-id <accepted-artifact-id> \
  --trusted-xcode-artifact-archive /absolute/path/to/exact-downloaded-actions-artifact.zip \
  --independent-crosscheck-receipt /absolute/path/to/PASS_NOT_FINAL_GO-receipt.json \
  --frozen-source-repo /absolute/path/to/frozen-source-repository \
  --tooling-repo /absolute/path/to/tooling-repository \
  --operator-attestation /absolute/path/to/operator-attestation.json \
  --output /absolute/path/to/NembraES80TodayFinalGO.json
```

`GITHUB_TOKEN` is optional for GitHub API authentication/rate-limit headroom. If used, keep it in the
process environment only; never write it into an artifact, attestation, command log, PR, or repository
file.

The repository supplied by `--frozen-source-repo` must contain the exact accepted app source commit
as a Git object. The repository supplied by `--tooling-repo` must contain the pinned independent
verifier commit as a Git object. The verifier resolves the required blobs with replacement/config
trust disabled; a shallow or incomplete clone that lacks those objects is a blocker, not permission
to skip the check.

The downloaded Actions ZIP is an authority subject. Do not unpack/repack it before verification. Its
local bytes must match GitHub's server-declared SHA-256 for the exact artifact record.

## Success and failure behavior

Success creates one new Final GO JSON using no-replace, failure-atomic publication. The tool prints
its exact output path and record SHA-256. It also prints:

`PHYSICAL RESULT COLLECTED: NO`

That statement remains true after Final GO creation. Final GO authorizes only the named stationary,
charger-disconnected, passive/read-only Experiment One procedure; it is not the physical result.

If any live GitHub subject, retained artifact, candidate record, signature/provisioning subject,
Research compile tuple, frozen Git blob, retained IPA digest, runtime rendezvous, preflight
observation, or attestation field disagrees, the tool exits NO-GO and must not publish a Final GO
record.

The output path is intentionally write-once. If a Final GO record already exists there, do not
overwrite it. Use a new evidence location only for a genuinely new accepted attempt/candidate.

## Final field transition

Only after the verifier successfully publishes the retained Final GO record:

1. re-check that the record names the exact intended accepted source/candidate;
2. keep the exact installed build unchanged;
3. keep charger disconnected and scooter stationary;
4. launch the accepted Capture flow through explicit operator action;
5. follow `docs/ES80_TODAY_PRIVATE_FIELD_RUNBOOK.md` exactly;
6. stop on any listed failure condition;
7. preserve the resulting raw Share artifact unchanged.

Before that publication, the only correct physical status is:

**NO-GO / DO NOT RUN EXPERIMENT ONE.**
