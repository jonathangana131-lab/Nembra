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

- helper commit: `9b5bde849e6b8f6b76e2a15abb52d643e3616a7a`
- helper path: `scripts/ci/es80_today_field_candidate_preflight.py`
- helper blob: `fcc2243c005c5f6df2d2f5bd8b8c948e785f07d8`
- exact focused QA run: `31340823325` — terminal success
- helper authority on every report: `operator-pre-signing-readiness-not-field-authorization`
- physical authorization on every report: `not-granted`

The helper exists only to prevent known operator-input dead ends before the frozen producer is invoked. The frozen `a0f4…` producer independently revalidates all authoritative signing/private-input conditions.

## Why an exact detached source checkout is mandatory

`scripts/ci/xcode27_today_research_field_candidate.sh` delegates to the canonical producer, which derives `SOURCE_SHA` from the invocation checkout's current Git `HEAD`. That is correct behavior, but it means running the wrapper from a newer moving `main` would deliberately produce a different-source candidate.

Therefore the operator must first establish and verify a clean detached checkout at exact `a0f4a33451f61411d6e0541f2e70edea5438342d`. Do not rely on branch names, a recently pulled `main`, PR prose, or a visually matching app.

## Private inputs

Have these available only on the private signing Mac:

- Apple `TeamIdentifier` for the intended signing identity;
- an existing valid Xcode export-options plist for that team/distribution method;
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

This handoff deliberately avoids shell redirection for the secret. Before the UDID is acquired, it resolves `$HOME` to a physical absolute path, opens that path component-by-component with `O_DIRECTORY|O_NOFOLLOW`, and pins `.nembra-private` by directory descriptor. It checks descriptor-relative that the final UDID name does not already exist **before prompting for the secret**, then creates the file with `O_CREAT|O_EXCL|O_NOFOLLOW` relative to the same pinned private-directory descriptor. The early check preserves the no-unnecessary-secret-acquisition contract for an already-existing path; `O_EXCL` remains the authoritative race-safe no-clobber guard if a file appears after that check.

This closes the creation-time parent-path retarget/symlink race that ordinary `> "$UDID_FILE"` redirection cannot close. The raw UDID is read from the terminal by isolated Python, is never placed in the command line or environment, and is written without a trailing newline.

The frozen producer and pinned preflight still independently validate the final pathname before using it. This creation helper does not grant field authorization and does not make later pathname substitution trustworthy.

```bash
umask 077
HOME_PHYSICAL="$(cd -P -- "$HOME" && /bin/pwd -P)"
test -n "$HOME_PHYSICAL" && test "${HOME_PHYSICAL#/}" != "$HOME_PHYSICAL"
PRIVATE_DIR="$HOME_PHYSICAL/.nembra-private"
UDID_FILE="$PRIVATE_DIR/es80-intended-device.udid"

/usr/bin/python3 -I - "$HOME_PHYSICAL" <<'PY'
import getpass
import os
import stat
import sys

home = sys.argv[1]
if not home.startswith("/") or home == "/":
    raise SystemExit("Refusing invalid physical home path.")

walk_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
root_fd = os.open("/", walk_flags)
current_fd = root_fd
private_fd = None
file_fd = None
created_file = False

try:
    for component in (part for part in home.split("/") if part):
        next_fd = os.open(component, walk_flags, dir_fd=current_fd)
        if current_fd != root_fd:
            os.close(current_fd)
        current_fd = next_fd

    try:
        os.mkdir(".nembra-private", 0o700, dir_fd=current_fd)
    except FileExistsError:
        pass

    private_fd = os.open(".nembra-private", walk_flags, dir_fd=current_fd)
    os.fchmod(private_fd, 0o700)

    try:
        os.stat(
            "es80-intended-device.udid",
            dir_fd=private_fd,
            follow_symlinks=False,
        )
    except FileNotFoundError:
        pass
    else:
        raise SystemExit("Refusing existing intended-device input path before secret acquisition.")

    value = getpass.getpass("Intended iPhone UDID: ")
    if not value or value != value.strip() or "\x00" in value:
        raise SystemExit("Refusing empty or whitespace/NUL-padded intended-device identifier.")

    create_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC
    file_fd = os.open(
        "es80-intended-device.udid",
        create_flags,
        0o600,
        dir_fd=private_fd,
    )
    created_file = True
    encoded = value.encode("utf-8")
    offset = 0
    while offset < len(encoded):
        written = os.write(file_fd, encoded[offset:])
        if written <= 0:
            raise OSError("short write while creating intended-device input")
        offset += written
    os.fsync(file_fd)

    metadata = os.fstat(file_fd)
    if not stat.S_ISREG(metadata.st_mode):
        raise SystemExit("Refusing non-regular intended-device input.")
    if stat.S_IMODE(metadata.st_mode) != 0o600:
        raise SystemExit("Refusing intended-device input with mode other than 0600.")
    if metadata.st_size != len(encoded) or metadata.st_size == 0:
        raise SystemExit("Refusing incomplete intended-device input write.")
except BaseException:
    if created_file and private_fd is not None:
        try:
            os.unlink("es80-intended-device.udid", dir_fd=private_fd)
        except OSError:
            pass
    raise
finally:
    if file_fd is not None:
        os.close(file_fd)
    if private_fd is not None:
        os.close(private_fd)
    if current_fd != root_fd:
        os.close(current_fd)
    os.close(root_fd)
PY

test -s "$UDID_FILE"
test -f "$UDID_FILE" && test ! -L "$UDID_FILE"
test "$(/usr/bin/stat -f '%Lp' "$UDID_FILE")" = '600'
```

If the final file already exists at the descriptor-relative precheck, the helper stops before asking for the UDID. If the name appears only after that check, `O_EXCL` still fails closed without replacing it. Preserve any existing path and choose a fresh private path rather than overwriting it. Keep the new file private; do not commit it and do not copy it into the retained candidate directory.

## 3. Set the signing inputs without changing the source subject

Set paths/values for the private Mac. `ARTIFACTS_DIR` must name a destination that does **not** already exist; the producer publishes it failure-atomically only after the archive/export/inspection sequence succeeds.

```bash
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

Keep `NEMBRA_ALLOW_PROVISIONING_UPDATES=0` unless the private signing setup actually requires Xcode-managed provisioning updates. If it must be `1`, make that an explicit operator choice; it does not change the frozen source SHA or grant field authorization.

## 3A. Run the accepted non-authorizing pre-signing preflight

Do not run a moving `main` copy of the helper and do not copy the helper into the frozen source checkout. Materialize the exact accepted helper bytes from a separate local Nembra tooling repository that contains commit `9b5bde849e6b8f6b76e2a15abb52d643e3616a7a`, then run those bytes against the exact frozen `FIELD_SOURCE`.

The helper deliberately reads the private signing values from the environment and the intended-device value only from its mode-`0600` file. Its JSON report omits the TeamIdentifier, raw UDID, private input paths, export-options contents, and dirty-checkout text.

```bash
PREFLIGHT_COMMIT='9b5bde849e6b8f6b76e2a15abb52d643e3616a7a'
PREFLIGHT_BLOB='fcc2243c005c5f6df2d2f5bd8b8c948e785f07d8'
TOOL_REPO='/absolute/path/to/a/local/Nembra/tooling-repository'
PREFLIGHT_DIR="$(/usr/bin/mktemp -d /tmp/nembra-es80-preflight.XXXXXX)"
PREFLIGHT="$PREFLIGHT_DIR/es80_today_field_candidate_preflight.py"
PREFLIGHT_REPORT="$PREFLIGHT_DIR/preflight.json"

cd "$TOOL_REPO"
/usr/bin/git cat-file -e "$PREFLIGHT_COMMIT^{commit}"
test "$(/usr/bin/git rev-parse --verify "$PREFLIGHT_COMMIT:scripts/ci/es80_today_field_candidate_preflight.py")" = "$PREFLIGHT_BLOB"
/usr/bin/git show "$PREFLIGHT_COMMIT:scripts/ci/es80_today_field_candidate_preflight.py" > "$PREFLIGHT"
test "$(/usr/bin/git hash-object --no-filters -- "$PREFLIGHT")" = "$PREFLIGHT_BLOB"

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

If the preflight exits nonzero, reports anything other than `READY_TO_INVOKE_SIGNED_FIELD_PRODUCER`, or the pinned helper blob cannot be materialized exactly, **stop before invoking the signed-field producer**. Correct only the reported local pre-signing blocker and rerun the exact pinned helper.

`READY_TO_INVOKE_SIGNED_FIELD_PRODUCER` means only that these local inputs are coherent enough to invoke the frozen producer. It is not signed-candidate acceptance, intended-device installation evidence, runtime provenance, Final GO, scooter identity, or permission to scan.

Keep the preflight report outside `ARTIFACTS_DIR`; do not mutate the producer's retained candidate shape with auxiliary files.

## 4. Produce exactly one Research Field Build candidate

Pass the private inputs only to the TODAY wrapper invocation:

```bash
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
- the pinned external preflight cannot be materialized exactly, exits nonzero, or does not report `READY_TO_INVOKE_SIGNED_FIELD_PRODUCER` for the exact frozen source;
- the producer reports any source, signing, provisioning, intended-device, export, inspection, or evidence failure;
- more than one IPA is exported or the retained `NembraField.ipa` is missing;
- the resulting evidence names a different source SHA, recipe, or build subject;
- the candidate destination existed before production or appears partially published after a failure;
- the private base path cannot be resolved to a physical absolute home path before secret acquisition;
- the private home path cannot be opened component-by-component without following symlinks, the private directory cannot be created/opened descriptor-relative, the final private file already exists before secret acquisition, or the exact mode-`0600` descriptor-relative `O_EXCL|O_NOFOLLOW` write cannot be completed and fsynced;
- the retained verification file is not mode-`0600` regular non-symlink input, or its final pathname traverses a symlinked ancestor / the Nembra repository when the pinned preflight revalidates it;
- the intended-device verification value contains leading/trailing whitespace/newline/NUL;
- the next step would require rebuilding, re-exporting, substituting another app/IPA, or using Xcode Run;
- anyone proposes Bluetooth scanning before the hardened Final GO record exists.

Do not improvise around a failed gate. The output of a failure is the exact failure evidence, not a weaker candidate.

## Cleanup after evidence is safely retained

The dedicated outer worktree and temporary preflight material can be removed after the retained candidate and required private evidence are safely preserved:

```bash
cd "$NEMBRA_REPO"
/usr/bin/git worktree remove --force "$FIELD_SOURCE"
/bin/rmdir "$FIELD_PARENT" 2>/dev/null || true
/bin/rm -rf "$PREFLIGHT_DIR"
```

Removing the source worktree or temporary preflight report does not authorize or invalidate the retained candidate. The retained candidate's own exact provenance/evidence remains authoritative for the next gate.

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO UNTIL THE EXACT SIGNED CANDIDATE, CROSS-CHECK, INSTALL/RUNTIME RENDEZVOUS, FRESH PREFLIGHT, AND HARDENED FINAL GO RECORD ARE ALL ACCEPTED.**