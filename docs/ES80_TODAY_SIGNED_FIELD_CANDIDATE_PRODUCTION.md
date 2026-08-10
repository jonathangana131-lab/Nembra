# ES80 TODAY Signed Research Field Candidate Production — V14

Status: **PRIVATE PRODUCTION HANDOFF ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

Purpose: make the next P0 Capture rung mechanically unambiguous now that the trusted software/Simulator gate for the frozen Capture subject is accepted. This procedure produces one signed, intended-device Research Field Build candidate from the exact frozen source and nothing more.

It does **not** authorize Bluetooth scanning, physical ES80 Experiment One, characteristic writes, scooter commands, or any telemetry claim. After production, the retained candidate still must pass independent inspection/cross-check, exact retained-IPA installation, Home-Screen runtime rendezvous, and the hardened Final GO procedure.

## Accepted frozen software subject

For the current TODAY handoff:

- Capture PR: `#833`
- exact frozen Capture source: `a0f4a33451f61411d6e0541f2e70edea5438342d`
- accepted trusted owner-command run: `31312741465`
- accepted trusted Mac authority job: `93243212531`
- accepted retained Simulator artifact: `9038098282`
- accepted retained Simulator artifact digest: `sha256:f128a9bd05b2ceff7be47addce103028d7bc6982ede17ad0bc8894983e826e72`
- Research recipe: `ES80-FINGERPRINT-v1`
- procedure: `V14`

The Simulator artifact above is software evidence only. It is **not** the signed field candidate and is not physical authorization.

The current accepted external pre-signing helper is also non-authorizing software tooling:

- helper commit: `74f4e88e4efb78bf69fe504f407ef42398e4b6ab`
- helper path: `scripts/ci/es80_today_field_candidate_preflight.py`
- helper blob: `1b0155ab8d990420c33ad4c65461e7663612f9fb`
- exact focused QA run: `31349183788` — terminal success
- exact focused QA job: `93336690257` — terminal success
- helper authority on every report: `operator-pre-signing-readiness-not-field-authorization`
- physical authorization on every report: `not-granted`

The helper exists only to prevent known operator-input dead ends before the frozen producer is invoked. It binds ExportOptions coherence to one exact descriptor-opened regular-file subject, rejecting relative paths, symlinked ancestors/final subjects, special files, and identity mutation while preserving the accepted TeamIdentifier/method checks. The frozen `a0f4…` producer independently revalidates all authoritative signing/private-input conditions.

Superseded preflight provenance, retained only to make the handoff history auditable: commit `9b5bde849e6b8f6b76e2a15abb52d643e3616a7a`, blob `fcc2243c005c5f6df2d2f5bd8b8c948e785f07d8`, run `31340823325`. **Do not materialize or invoke that superseded helper for the current handoff.**

## Why an exact detached source checkout is mandatory

`scripts/ci/xcode27_today_research_field_candidate.sh` delegates to the canonical producer, which derives `SOURCE_SHA` from the invocation checkout's current Git `HEAD`. That is correct behavior, but it means running the wrapper from a newer moving `main` would deliberately produce a different-source candidate.

Therefore the operator must first establish and verify a clean detached checkout at exact `a0f4a33451f61411d6e0541f2e70edea5438342d`. Do not rely on branch names, a recently pulled `main`, PR prose, or a visually matching app.

## Private inputs

Have these available only on the private signing Mac:

- Apple `TeamIdentifier` for the intended signing identity;
- an existing valid Xcode export-options plist for that team/distribution method, at one absolute regular non-symlink path with no symlinked ancestor;
- the intended iPhone's UDID, stored in one absolute mode-`0600` regular non-symlink file;
- Xcode 27 and the intended iPhone 12 / iOS 27;
- signing/provisioning credentials needed by Xcode.

Do not place the raw intended-device UDID in GitHub, PR comments, command arguments, screenshots, artifact names, or public durable notes.

## 1. Establish the exact frozen source

Start from a clean local Nembra repository that contains the accepted commit object. Use a dedicated detached worktree so moving `main` cannot silently become the build subject.

```bash
set -euo pipefail

SOURCE_SHA='a0f4a33451f61411d6e0541f2e70edea5438342d'
NEMBRA_REPO='/absolute/path/to/your/clean/Nembra'
FIELD_PARENT="$(/usr/bin/mktemp -d /tmp/nembra-es80-a0f4.XXXXXX)"
FIELD_SOURCE="$FIELD_PARENT/source"

cd "$NEMBRA_REPO"
/usr/bin/git cat-file -e "$SOURCE_SHA^{commit}"
/usr/bin/git worktree add --detach "$FIELD_SOURCE" "$SOURCE_SHA"
cd "$FIELD_SOURCE"

test "$(/usr/bin/git rev-parse --verify HEAD^{commit})" = "$SOURCE_SHA"
test -z "$(/usr/bin/git status --porcelain=v1 --untracked-files=all)"
```

If the commit object is not present locally, obtain that exact object through the normal trusted repository remote before continuing, then repeat the checks. Do not substitute another SHA merely because it is newer.

The producer itself will create another fresh detached worktree internally. The outer detached worktree here prevents the operator from accidentally invoking that producer from the wrong repository HEAD.

## 2. Create the private intended-device verification file

Choose a private path outside the repository. The producer requires an absolute regular non-symlink mode-`0600` file and independently validates its contents/mode.

Do not acquire the raw identifier through ordinary shell redirection. Even with `noclobber`, a checked parent directory pathname can be renamed and replaced before `> "$UDID_FILE"` re-resolves it. Use the accepted descriptor-bound private-input helper instead.

The accepted private-input helper identity is fixed below:

- helper commit: `af75ffa6dc4409a21822295428e4eeb922ac3d16`
- helper path: `scripts/ci/es80_today_private_device_input.py`
- helper blob: `50b12675a57fd2f570d833cfcdbfd7be59f52ca4`
- exact focused QA run: `31349855525` — terminal success
- exact focused QA job: `93338506616` — terminal success

Those accepted bytes minimize secret acquisition and preserve custody across failure: an already-occupied final path is refused before the private identifier is requested; secure terminal input fails closed on echoed-fallback warning or EOF; descriptor-relative `O_EXCL|O_NOFOLLOW` remains the race authority after the precheck; fresh inode mode/ownership/link/size are proven before secret bytes are written; failed acquisition durably scrubs the exact open inode and/or proves safe exact-inode unlink; terminal abort follows the same cleanup boundary; pathname retarget is rejected; and successful output is rebound to the same directory/file identity with exact byte readback. These helper bytes are operator-custody tooling only. They do not alter the frozen `a0f4…` app subject, accept signing, or authorize Bluetooth activity.

```bash
umask 077
HOME_PHYSICAL="$(cd -P -- "$HOME" && /bin/pwd -P)"
test -n "$HOME_PHYSICAL" && test "${HOME_PHYSICAL#/}" != "$HOME_PHYSICAL"
PRIVATE_DIR="$HOME_PHYSICAL/.nembra-private"
UDID_FILE="$PRIVATE_DIR/es80-intended-device.udid"
TOOL_REPO='/absolute/path/to/a/local/Nembra/tooling-repository'

PRIVATE_INPUT_HELPER_COMMIT='af75ffa6dc4409a21822295428e4eeb922ac3d16'
PRIVATE_INPUT_HELPER_BLOB='50b12675a57fd2f570d833cfcdbfd7be59f52ca4'
PRIVATE_INPUT_HELPER_DIR="$(/usr/bin/mktemp -d /tmp/nembra-es80-private-input.XXXXXX)"
PRIVATE_INPUT_HELPER="$PRIVATE_INPUT_HELPER_DIR/es80_today_private_device_input.py"

cd "$TOOL_REPO"
/usr/bin/git cat-file -e "$PRIVATE_INPUT_HELPER_COMMIT^{commit}"
test "$(/usr/bin/git rev-parse --verify "$PRIVATE_INPUT_HELPER_COMMIT:scripts/ci/es80_today_private_device_input.py")" = "$PRIVATE_INPUT_HELPER_BLOB"
/usr/bin/git show "$PRIVATE_INPUT_HELPER_COMMIT:scripts/ci/es80_today_private_device_input.py" > "$PRIVATE_INPUT_HELPER"
test "$(/usr/bin/git hash-object --no-filters -- "$PRIVATE_INPUT_HELPER")" = "$PRIVATE_INPUT_HELPER_BLOB"

/usr/bin/python3 -I "$PRIVATE_INPUT_HELPER" \
  --private-directory "$PRIVATE_DIR" \
  --source-repo "$FIELD_SOURCE"

test -f "$UDID_FILE" && test ! -L "$UDID_FILE"
test "$(/usr/bin/stat -f '%Lp' "$UDID_FILE")" = '600'
```

If the helper reports `NOT_READY`, cannot establish secure terminal input, is interrupted, or reports that failed-input cleanup could not be proven durable, stop before signing and preserve the exact non-secret blocker/abort. Do not fall back to `printf >`, `tee`, `echo`, `noclobber`, or another pathname-based secret write. Keep the resulting file private; do not commit it and do not copy it into the retained candidate directory. If the chosen final path already exists, preserve it and choose a fresh filename/path rather than deleting or overwriting it just to satisfy the helper.

## 3. Set the signing inputs without changing the source subject

Set paths/values for the private Mac. `ARTIFACTS_DIR` must name a destination that does **not** already exist; the producer publishes it failure-atomically only after the archive/export/inspection sequence succeeds.

The accepted preflight deliberately verifies the Xcode selected by `/usr/bin/xcode-select` inside a closed child environment. The frozen `a0f4…` producer predates that helper and does not scrub a caller-provided `DEVELOPER_DIR` before invoking `xcodebuild`. A shell-level `DEVELOPER_DIR` override could therefore make preflight validate one Xcode while the frozen producer later uses another. This handoff closes that operator split without changing the frozen product: clear `DEVELOPER_DIR` before preflight, keep it absent through production, and configure the private Mac's Xcode 27 selection through `xcode-select` instead of a per-shell override.

```bash
unset DEVELOPER_DIR
test -z "${DEVELOPER_DIR+x}"

NEMBRA_DEVELOPMENT_TEAM='<10-character Apple TeamIdentifier>'
NEMBRA_EXPORT_OPTIONS_PLIST='/absolute/private/path/ExportOptions.plist'
NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE="$UDID_FILE"
NEMBRA_ALLOW_PROVISIONING_UPDATES=0

CANDIDATE_PARENT='/absolute/private/path/to/nembra-field-candidates'
/bin/mkdir -p "$CANDIDATE_PARENT"
ARTIFACTS_DIR="$CANDIDATE_PARENT/NembraFieldCandidate-a0f4-$(/bin/date -u '+%Y%m%dT%H%M%SZ')"

test ! -e "$ARTIFACTS_DIR"
/usr/bin/plutil -lint "$NEMBRA_EXPORT_OPTIONS_PLIST"
test "$(/usr/bin/git rev-parse --verify HEAD^{commit})" = "$SOURCE_SHA"
test -z "$(/usr/bin/git status --porcelain=v1 --untracked-files=all)"
```

Keep `NEMBRA_ALLOW_PROVISIONING_UPDATES=0` unless the private signing setup actually requires Xcode-managed provisioning updates. If it must be `1`, make that an explicit operator choice; it does not change the frozen source SHA or grant field authorization. If Xcode 27 is not the system-selected Xcode, correct the private Mac's `xcode-select` selection before continuing; do not reintroduce `DEVELOPER_DIR` merely to make the preflight or producer pass.

## 3A. Run the accepted non-authorizing pre-signing preflight

Do not run a moving `main` copy of the helper and do not copy the helper into the frozen source checkout. Materialize the exact accepted helper bytes from a separate local Nembra tooling repository that contains commit `74f4e88e4efb78bf69fe504f407ef42398e4b6ab`, then run those bytes against the exact frozen `FIELD_SOURCE`.

The helper deliberately reads the private signing values from the environment and the intended-device value only from its mode-`0600` file. Its JSON report omits the TeamIdentifier, raw UDID, private input paths, export-options contents, and dirty-checkout text. It fails closed unless the ExportOptions subject is one absolute, non-empty regular file reached without symlinked ancestors/final subjects, remains the same file while parsed, and satisfies the accepted TeamIdentifier/method coherence rules.

```bash
PREFLIGHT_COMMIT='74f4e88e4efb78bf69fe504f407ef42398e4b6ab'
PREFLIGHT_BLOB='1b0155ab8d990420c33ad4c65461e7663612f9fb'
PREFLIGHT_DIR="$(/usr/bin/mktemp -d /tmp/nembra-es80-preflight.XXXXXX)"
PREFLIGHT="$PREFLIGHT_DIR/es80_today_field_candidate_preflight.py"
PREFLIGHT_REPORT="$PREFLIGHT_DIR/preflight.json"

cd "$TOOL_REPO"
/usr/bin/git cat-file -e "$PREFLIGHT_COMMIT^{commit}"
test "$(/usr/bin/git rev-parse --verify "$PREFLIGHT_COMMIT:scripts/ci/es80_today_field_candidate_preflight.py")" = "$PREFLIGHT_BLOB"
/usr/bin/git show "$PREFLIGHT_COMMIT:scripts/ci/es80_today_field_candidate_preflight.py" > "$PREFLIGHT"
test "$(/usr/bin/git hash-object --no-filters -- "$PREFLIGHT")" = "$PREFLIGHT_BLOB"

test -z "${DEVELOPER_DIR+x}"
NEMBRA_DEVELOPMENT_TEAM="$NEMBRA_DEVELOPMENT_TEAM" \
NEMBRA_EXPORT_OPTIONS_PLIST="$NEMBRA_EXPORT_OPTIONS_PLIST" \
NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" \
NEMBRA_ALLOW_PROVISIONING_UPDATES="$NEMBRA_ALLOW_PROVISIONING_UPDATES" \
/usr/bin/python3 -I "$PREFLIGHT" \
  --source-repo "$FIELD_SOURCE" \
  --expected-source-sha "$SOURCE_SHA" \
  > "$PREFLIGHT_REPORT"

/usr/bin/python3 -I - "$PREFLIGHT_REPORT" "$SOURCE_SHA" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
expected_source = sys.argv[2]
assert report["status"] == "READY_TO_INVOKE_SIGNED_FIELD_PRODUCER"
assert report["authority"] == "operator-pre-signing-readiness-not-field-authorization"
assert report["physicalExperimentAuthorization"] == "not-granted"
assert report["sourceCommitSHA"] == expected_source
PY

cd "$FIELD_SOURCE"
test "$(/usr/bin/git rev-parse --verify HEAD^{commit})" = "$SOURCE_SHA"
test -z "$(/usr/bin/git status --porcelain=v1 --untracked-files=all)"
```

If the preflight exits nonzero, reports anything other than `READY_TO_INVOKE_SIGNED_FIELD_PRODUCER`, the pinned helper blob cannot be materialized exactly, or the ExportOptions path/coherence/custody checks fail, **stop before invoking the signed-field producer**. Correct only the reported local pre-signing blocker and rerun the exact pinned helper.

`READY_TO_INVOKE_SIGNED_FIELD_PRODUCER` means only that these local inputs are coherent enough to invoke the frozen producer. It is not signed-candidate acceptance, intended-device installation evidence, runtime provenance, Final GO, scooter identity, or permission to scan.

Keep the preflight report outside `ARTIFACTS_DIR`; do not mutate the producer's retained candidate shape with auxiliary files.

## 4. Produce exactly one Research Field Build candidate

Pass the private inputs only to the TODAY wrapper invocation. Reassert the `DEVELOPER_DIR` absence immediately before entering the frozen wrapper so the producer cannot silently diverge from the Xcode selection the preflight just checked:

```bash
test -z "${DEVELOPER_DIR+x}"
NEMBRA_DEVELOPMENT_TEAM="$NEMBRA_DEVELOPMENT_TEAM" \
NEMBRA_EXPORT_OPTIONS_PLIST="$NEMBRA_EXPORT_OPTIONS_PLIST" \
NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" \
NEMBRA_ALLOW_PROVISIONING_UPDATES="$NEMBRA_ALLOW_PROVISIONING_UPDATES" \
ARTIFACTS_DIR="$ARTIFACTS_DIR" \
./scripts/ci/xcode27_today_research_field_candidate.sh
```

Do **not** invoke `scripts/ci/xcode27_signed_field_candidate.sh` directly for TODAY. The wrapper is the accepted path that explicitly selects the private research compile mode and causes the canonical producer to compile `NEMBRA_ES80_TODAY_RESEARCH` only for the physical-iOS Release archive.

A successful command is still candidate production, not Final GO.

## 5. Require the retained output shape before doing anything else

After successful production, keep the published candidate directory unchanged. At minimum, require the canonical retained subjects to exist:

```bash
EXTERNAL_RECORD="$ARTIFACTS_DIR/inspection/NembraCaptureExternalBuildRecord.json"
FIELD_RECORD="$ARTIFACTS_DIR/inspection/NembraCaptureFieldBuildEvidenceRecord.json"
SIGNING_INSPECTION="$ARTIFACTS_DIR/inspection/NembraCaptureSignedFieldArtifactInspection.json"
IPA="$ARTIFACTS_DIR/inspection/build-evidence/NembraField.ipa"

for subject in "$EXTERNAL_RECORD" "$FIELD_RECORD" "$SIGNING_INSPECTION" "$IPA"; do
  test -f "$subject" && test ! -L "$subject"
done

IPA_SHA256="$(/usr/bin/shasum -a 256 "$IPA" | /usr/bin/awk '{print $1}')"
printf 'Retained candidate: %s\nRetained IPA SHA-256: %s\n' "$ARTIFACTS_DIR" "$IPA_SHA256"
```

Do not rename/re-export/rebuild the IPA. Do not install an `.app` from DerivedData or press Xcode Run.

The canonical producer/inspector evidence must independently prove, among its required fields, the exact frozen source, intended-device authorization, Apple signing identity, build identifier, build-instance ID, `ES80-FINGERPRINT-v1`, executable SHA-256, raw Info.plist SHA-256, and retained IPA SHA-256.

If any subject is missing, any exact identity does not match, or production came from a SHA other than `a0f4a33451f61411d6e0541f2e70edea5438342d`, stop. Do not repair the retained directory in place and do not continue to installation.

## 6. Continue only through the accepted retained-IPA handoff

The next procedure is:

`docs/ES80_TODAY_EXACT_RETAINED_IPA_INSTALL.md`

It requires the pinned independent retained-candidate cross-check, frozen-source producer/inspector Git-blob reconciliation, pre-install IPA digest, exact retained-IPA installation through Xcode device management, Home-Screen runtime source/build/build-instance/recipe rendezvous, and post-install digest equality.

`PASS_NOT_FINAL_GO` from the independent cross-check remains non-authorizing.

After installation/rendezvous, complete the operator attestation and hardened Final GO procedure documented by:

`docs/ES80_TODAY_FINAL_GO_OPERATOR_ATTESTATION.md`

Only an accepted Final GO record for the exact signed/install/runtime evidence can make the separate stationary, charger-disconnected, passive/read-only Experiment One eligible.

## Stop conditions

Stop and preserve the exact blocker if any of these occurs:

- the outer checkout is not exact clean detached `a0f4a33451f61411d6e0541f2e70edea5438342d`;
- `DEVELOPER_DIR` is set or reintroduced after Section 3; configure Xcode 27 through the private Mac's `xcode-select` selection instead of carrying a caller override into the frozen producer;
- the descriptor-bound private-input helper cannot be materialized at exact commit/blob, cannot establish secure no-echo terminal input, refuses the parent/input, is interrupted, reports unproven durable cleanup, or cannot create and rebind one fresh exact mode-`0600` single-link file;
- the pinned external preflight cannot be materialized exactly, exits nonzero, or does not report `READY_TO_INVOKE_SIGNED_FIELD_PRODUCER` for the exact frozen source;
- the ExportOptions plist path is not absolute, traverses a symlinked ancestor, names a symlink/non-regular/empty subject, changes identity while parsed, has a mismatched optional `teamID`, or has an invalid optional `method`;
- the producer reports any source, signing, provisioning, intended-device, export, inspection, or evidence failure;
- more than one IPA is exported or the retained `NembraField.ipa` is missing;
- the resulting evidence names a different source SHA, recipe, or build subject;
- the candidate destination existed before production or appears partially published after a failure;
- the private base path cannot be resolved to a physical absolute home path before secret acquisition;
- the intended-device input path traverses the frozen source repository, any private-directory component is symlinked/unsafe, the final private path already exists, or the retained verification file is not exact mode-`0600` regular single-link input;
- the intended-device verification value contains leading/trailing whitespace/newline or control characters;
- the next step would require rebuilding, re-exporting, substituting another app/IPA, or using Xcode Run;
- anyone proposes Bluetooth scanning before the hardened Final GO record exists.

Do not improvise around a failed gate. The output of a failure is the exact failure evidence, not a weaker candidate.

## Cleanup after evidence is safely retained

The dedicated outer worktree and temporary helper/preflight material can be removed after the retained candidate and required private evidence are safely preserved:

```bash
cd "$NEMBRA_REPO"
/usr/bin/git worktree remove --force "$FIELD_SOURCE"
/bin/rmdir "$FIELD_PARENT" 2>/dev/null || true
/bin/rm -rf "$PRIVATE_INPUT_HELPER_DIR" "$PREFLIGHT_DIR"
```

Removing the source worktree or temporary helper/preflight reports does not authorize or invalidate the retained candidate. The retained candidate's own exact provenance/evidence remains authoritative for the next gate.

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO UNTIL THE EXACT SIGNED CANDIDATE, CROSS-CHECK, INSTALL/RUNTIME RENDEZVOUS, FRESH PREFLIGHT, AND HARDENED FINAL GO RECORD ARE ALL ACCEPTED.**
