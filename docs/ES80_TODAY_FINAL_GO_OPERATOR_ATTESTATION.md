# ES80 TODAY Final GO Operator Attestation — V14

Status: **SUPPORTING PRIVATE TODAY PROCEDURE ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO UNTIL THE HARDENED FINAL GO RECORD IS SUCCESSFULLY ISSUED.**

Purpose: provide the exact closed-world JSON shape consumed by `scripts/ci/es80_today_final_go_hardened.py` after the trusted Xcode artifact, signed Research Field Build, independent `PASS_NOT_FINAL_GO` cross-check, exact retained-IPA installation, Home-Screen runtime rendezvous, and fresh stationary/charger-disconnected preflight have all been independently checked.

This file is an operator-procedure aid. It does not mint machine evidence, physical ES80 truth, Bluetooth write/command authority, or permission to skip any gate in `docs/ES80_TODAY_PRIVATE_FIELD_RUNBOOK.md` or `docs/ES80_TODAY_EXACT_RETAINED_IPA_INSTALL.md`.

## When to create the attestation

Create the attestation **only after** all of these have actually been observed for the exact accepted retained candidate:

- the trusted retained Simulator artifact has been inspected and no TODAY blocker remains;
- the exact retained signed IPA passed canonical signing/provisioning/intended-device inspection;
- the pinned external cross-check returned `PASS_NOT_FINAL_GO` for the exact candidate;
- the retained IPA SHA-256 was checked immediately before installation;
- that exact retained IPA was installed through Xcode device management without rebuild, re-export, or substitution;
- Nembra was launched from the iPhone Home Screen, not Xcode Run;
- runtime source/build/build-instance/recipe exactly rendezvoused with retained evidence;
- package-owned TODAY ResearchAdmission was visibly available and ordinary/general build authority remained NO-GO;
- the original retained IPA SHA-256 was checked again after installation and remained identical;
- the accepted Capture preflight is healthy;
- the charger is freshly confirmed disconnected;
- the scooter is stationary;
- explicit operator action is still required to start Capture;
- the application path has been reviewed as having no characteristic-write or scooter-command authority for Experiment One.

If any item is unknown, failed, stale, or ambiguous, do **not** create an affirmative attestation. Preserve the exact blocker instead.

## Freshness requirement

`recordedAtUTC` is intentionally short-lived procedure evidence. At hardened Final GO evaluation it must:

- be normalized UTC text ending in `Z`;
- not be more than 5 minutes in the future; and
- not be more than **30 minutes old**.

That 30-minute window exists because charger state, stationary setup, preflight health, and installed runtime state can change. Do not prepare a positive attestation hours in advance and do not edit an old attestation's timestamp to make stale observations appear fresh. If the window expires, repeat the relevant live observations and create a new attestation with a new lowercase UUID.

## Exact JSON shape

The validator rejects missing keys, unknown extra keys, duplicate JSON keys, wrong literals, malformed IDs/digests, stale timestamps, and any candidate/runtime mismatch.

Replace every `<...>` placeholder below with the exact independently checked value. Do not leave angle-bracket placeholders in the submitted file.

```json
{
  "schemaVersion": 1,
  "authority": "operator-field-attestation-not-machine-evidence",
  "attestationID": "<new lowercase UUID>",
  "recordedAtUTC": "<fresh UTC timestamp, for example 2026-08-09T12:34:00Z>",
  "simulatorArtifactReview": "INSPECTED_NO_TODAY_BLOCKER",
  "installationRoute": "exact-retained-ipa-via-xcode-device-management",
  "preInstallRetainedIPASHA256": "<exact accepted retained IPA lowercase SHA-256>",
  "postInstallRetainedIPASHA256": "<the same exact retained IPA lowercase SHA-256>",
  "installedWithoutRebuildOrSubstitution": true,
  "installedOnIntendedDevice": true,
  "observedDevice": "iPhone 12",
  "observedOS": "iOS 27",
  "runtimeVisibleSourceCommitSHA": "<exact frozen 40-hex Capture source SHA>",
  "runtimeVisibleBuildIdentifier": "<exact runtime-visible Capture build identifier>",
  "runtimeVisibleBuildInstanceID": "<exact runtime-visible lowercase build-instance UUID>",
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

The two IPA digest fields intentionally contain the **same retained-file SHA-256**. This proves that the local retained install subject did not change during the handoff; it does not claim that iOS exposes or preserves an on-device IPA byte image.

## Safe local creation

Keep the attestation local/private with the rest of the TODAY Final GO evidence. Do not put the raw intended-device UDID in this JSON, GitHub, screenshots, artifact names, shell command arguments, or public notes.

A lowercase UUID and normalized UTC timestamp can be generated without asserting any procedure outcome:

```bash
ATTESTATION_ID="$(/usr/bin/uuidgen | /usr/bin/tr 'A-F' 'a-f')"
RECORDED_AT_UTC="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf 'attestationID=%s\nrecordedAtUTC=%s\n' "$ATTESTATION_ID" "$RECORDED_AT_UTC"
```

Those commands generate identifiers only. They do not authorize setting any affirmative observation field. Populate the JSON only from observations you actually completed.

Write the completed JSON to one new regular non-symlink file, for example:

```text
/private/path/es80-today-operator-attestation.json
```

Do not reuse a previously accepted file for a later attempt. The hardened publisher is failure-atomic and the operator attestation is attempt-specific.

## Private intended-device input

The hardened Final-GO executable also performs a fresh signed-candidate reinspection and therefore requires the intended-device identifier through a **private file path**:

```text
--intended-device-udid-file /private/path/intended-device-udid.txt
```

The file must contain the verification-only intended iPhone UDID and must remain local/private. Use the same private intended-device subject that was admitted for signed-field production; do not copy the raw UDID into the command line itself, the attestation JSON, GitHub, screenshots, artifact names, or public notes. The argument passes only the pathname to the private file.

If the private file is missing, points at the wrong intended device, cannot satisfy the hardened reinspection contract, or would require exposing the raw UDID to continue, stop and remain NO-GO.

## Exact Final GO executable-bundle custody

The hardened composer is itself authority-bearing: its output can contain `decision = GO`. Therefore `--tooling-repo` being pinned for the independent cross-check is not enough by itself. Do **not** run a moving `main`, an arbitrary local checkout, a copied script, or locally modified sibling modules as the process that mints Final GO.

The accepted executable bundle for the current TODAY procedure is the exact hosted-green #1730 head:

- exact tooling head: `4506bf3b0a523ca03fc09e968f34d4359e34bf91`;
- Final GO authority QA: run `31312717529`, job `93242924865` — terminal success;
- Final GO hardening QA: run `31312717536`, job `93242924588` — terminal success;
- `scripts/ci/es80_today_final_go_hardened.py` blob: `1b9560bad5a8a1ceb2934f91621be231f20a8a17`;
- `scripts/ci/_es80_today_final_go_foundation_impl.py` blob: `11a571b4439829f2c3bfe94b46e0598600238d89`;
- `scripts/ci/es80_today_trusted_capture_xcode_subject.py` blob: `94d19c0c0456860ead9a2003511c66c21d41c31a`;
- `scripts/ci/es80_today_final_go_publication.py` blob: `1593f00e5950935ed8c1b0514ae11f69be3a6f50`;
- `scripts/ci/es80_today_crosscheck_receipt_custody.py` blob: `3bea883a17c9a34e8d9dd5b258824d29257886f2`;
- `scripts/ci/es80_today_trusted_signed_candidate_reinspection.py` blob: `179cb50cb1f32595722cd2a53df47111a2ca6a45`.

Those six local modules are the executable authority bundle loaded by the hardened entrypoint. The trusted signed-candidate module separately materializes its reviewed private runner and canonical inspector from the frozen Capture source by their own pinned Git objects; those downstream tool bytes remain under that existing contract.

Create a dedicated detached tooling worktree and verify both the exact commit and the raw checkout bytes **before** the fresh Final GO invocation:

```bash
set -euo pipefail

FINAL_GO_TOOLING_HEAD='4506bf3b0a523ca03fc09e968f34d4359e34bf91'
TOOLING_REPO='/absolute/path/to/a/local/Nembra/tooling-repository'
FINAL_GO_TOOLING_PARENT="$(/usr/bin/mktemp -d /tmp/nembra-es80-final-go-tooling.XXXXXX)"
FINAL_GO_TOOLING_SOURCE="$FINAL_GO_TOOLING_PARENT/source"

/usr/bin/git -C "$TOOLING_REPO" cat-file -e "$FINAL_GO_TOOLING_HEAD^{commit}"
/usr/bin/git -C "$TOOLING_REPO" worktree add --detach "$FINAL_GO_TOOLING_SOURCE" "$FINAL_GO_TOOLING_HEAD"
test "$(/usr/bin/git -C "$FINAL_GO_TOOLING_SOURCE" rev-parse --verify HEAD^{commit})" = "$FINAL_GO_TOOLING_HEAD"
test -z "$(/usr/bin/git -C "$FINAL_GO_TOOLING_SOURCE" status --porcelain=v1 --untracked-files=all)"

verify_final_go_blob() {
  path="$1"
  expected="$2"
  test "$(/usr/bin/git -C "$FINAL_GO_TOOLING_SOURCE" rev-parse --verify "$FINAL_GO_TOOLING_HEAD:$path")" = "$expected"
  test "$(/usr/bin/git -C "$FINAL_GO_TOOLING_SOURCE" hash-object --no-filters -- "$path")" = "$expected"
}

verify_final_go_blob scripts/ci/es80_today_final_go_hardened.py 1b9560bad5a8a1ceb2934f91621be231f20a8a17
verify_final_go_blob scripts/ci/_es80_today_final_go_foundation_impl.py 11a571b4439829f2c3bfe94b46e0598600238d89
verify_final_go_blob scripts/ci/es80_today_trusted_capture_xcode_subject.py 94d19c0c0456860ead9a2003511c66c21d41c31a
verify_final_go_blob scripts/ci/es80_today_final_go_publication.py 1593f00e5950935ed8c1b0514ae11f69be3a6f50
verify_final_go_blob scripts/ci/es80_today_crosscheck_receipt_custody.py 3bea883a17c9a34e8d9dd5b258824d29257886f2
verify_final_go_blob scripts/ci/es80_today_trusted_signed_candidate_reinspection.py 179cb50cb1f32595722cd2a53df47111a2ca6a45
```

If the commit is unavailable, the worktree is not exact/clean, or any Git-tree/raw-checkout blob check differs, stop and remain NO-GO. Do not substitute a newer checkout merely because it is current and do not copy only the hardened entrypoint into another directory. The executing entrypoint and its sibling authority modules are one accepted bundle.

Keep this exact detached worktree unchanged through Final GO evaluation. Invoke the composer with isolated system Python from the verified bundle and pass that same exact worktree as `--tooling-repo`:

```text
/usr/bin/python3 -I "$FINAL_GO_TOOLING_SOURCE/scripts/ci/es80_today_final_go_hardened.py" \
  ... \
  --tooling-repo "$FINAL_GO_TOOLING_SOURCE" \
  ...
```

The `...` placeholders above are documentation shorthand only; do not literally pass them. Supply every required evidence argument listed below from the exact accepted candidate/installation/runtime subjects. After the Final GO attempt is complete and its evidence is safely retained, remove the dedicated tooling worktree through the original tooling repository rather than modifying it in place.

## Hardened Final GO invocation boundary

The private foundation implementation is deliberately non-authorizing when executed directly. Use only the hardened entrypoint from the exact verified tooling bundle above:

```text
/usr/bin/python3 -I "$FINAL_GO_TOOLING_SOURCE/scripts/ci/es80_today_final_go_hardened.py"
```

Its required evidence inputs include:

- `--candidate-root`
- `--expected-source-sha`
- `--expected-pr-number`
- `--trusted-xcode-run-id`
- `--trusted-xcode-job-id`
- `--trusted-xcode-artifact-id`
- `--trusted-xcode-artifact-archive`
- `--independent-crosscheck-receipt`
- `--frozen-source-repo`
- `--tooling-repo "$FINAL_GO_TOOLING_SOURCE"`
- `--operator-attestation`
- `--intended-device-udid-file`
- `--output`

Do not infer those identifiers from stale PR prose. Use the exact accepted retained evidence and live GitHub subject that passed the current pinned authority contract. For `--intended-device-udid-file`, pass only the path to the local private verification file; never substitute the raw identifier as an argument value.

A successful hardened invocation creates a **procedural Final GO record**, not a physical result. Inspect its exact bytes and require the intended `decision = GO`, accepted source/build/install/runtime subjects, recipe `ES80-FINGERPRINT-v1`, procedure `V14`, baseline iPhone 12 / iOS 27, ordinary/general build authority `NO-GO`, expected raw Share artifact, stop conditions, and `physicalResultCollected = false`.

Only after that exact Final GO record exists may the separate runbook transition to the first stationary, charger-disconnected, passive/read-only Experiment One. No Bluetooth characteristic write or scooter command becomes authorized.

## Fail closed

Stop and remain NO-GO if:

- any exact JSON literal above would be false or unobserved;
- the attestation would be older than 30 minutes at Final GO evaluation;
- pre/post retained IPA digests differ;
- installed/runtime tuple differs from retained evidence;
- package ResearchAdmission is unavailable or ordinary/general authority is not visibly NO-GO;
- preflight is not Ready;
- charger state is not freshly Disconnected;
- scooter cannot remain Stationary;
- explicit operator action is not required;
- application write/command authority exists or is uncertain;
- the trusted Xcode run/artifact is not the exact accepted current-authority subject;
- the Final GO executable bundle is not exact clean `4506bf3b0a523ca03fc09e968f34d4359e34bf91` with all six raw checkout blobs matching the accepted Git objects;
- the private intended-device UDID file is missing, wrong, exposed, or fails fresh signed-candidate reinspection;
- any retained/cross-check/signing/install evidence is missing or ambiguous.

The correct output is the exact blocker, not a guessed affirmative field.

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO UNTIL THE HARDENED FINAL GO RECORD IS COMPLETE AND ACCEPTED.**