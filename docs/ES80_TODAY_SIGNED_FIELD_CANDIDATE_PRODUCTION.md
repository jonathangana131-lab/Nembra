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

Choose a private path outside the repository. The producer requires an absolute regular non-symlink mode-`0600` file and independently validates its contents/mode. The file must contain the exact identifier bytes with **no trailing newline or other leading/trailing whitespace**; frozen `a0f4` rejects whitespace rather than trimming it.

This example also refuses a symlink private directory or any pre-existing final path **before** the secret is read or written. Bash `noclobber` supplies a second fail-closed guard against a target appearing between the pre-check and redirection. Do not weaken these checks into a write-then-validate sequence: shell redirection can follow a symlink before a later `test ! -L` has a chance to reject it.

```bash
umask 077
PRIVATE_DIR="$HOME/.nembra-private"
UDID_FILE="$PRIVATE_DIR/es80-intended-device.udid"

if [[ -L "$PRIVATE_DIR" ]]; then
  printf 'Refusing symlink private directory. Choose a real private directory.\n' >&2
  exit 1
fi
/bin/mkdir -p "$PRIVATE_DIR"
test -d "$PRIVATE_DIR" && test ! -L "$PRIVATE_DIR"
/bin/chmod 700 "$PRIVATE_DIR"

if [[ -e "$UDID_FILE" || -L "$UDID_FILE" ]]; then
  printf 'Refusing existing intended-device input path. Choose a fresh private path.\n' >&2
  exit 1
fi

printf 'Intended iPhone UDID: ' >&2
IFS= read -r -s INTENDED_UDID
printf '\n' >&2
( set -o noclobber; printf '%s' "$INTENDED_UDID" > "$UDID_FILE" )
unset INTENDED_UDID
/bin/chmod 600 "$UDID_FILE"

test -s "$UDID_FILE"
test -f "$UDID_FILE" && test ! -L "$UDID_FILE"
test "$(/usr/bin/stat -f '%Lp' "$UDID_FILE")" = '600'
```

Keep this file private. Do not commit it and do not copy it into the retained candidate directory. Do not "fix" it by adding a conventional final newline: this private verification subject is intentionally one exact opaque value. If the chosen path already exists, preserve it and choose a fresh path rather than overwriting or following it.

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
- the producer reports any source, signing, provisioning, intended-device, export, inspection, or evidence failure;
- more than one IPA is exported or the retained `NembraField.ipa` is missing;
- the resulting evidence names a different source SHA, recipe, or build subject;
- the candidate destination existed before production or appears partially published after a failure;
- the intended-device verification directory is a symlink, the final private path already exists, the private write cannot be created with noclobber, or the retained verification file is not mode `0600` regular non-symlink input;
- the intended-device verification value contains leading/trailing whitespace/newline;
- the next step would require rebuilding, re-exporting, substituting another app/IPA, or using Xcode Run;
- anyone proposes Bluetooth scanning before the hardened Final GO record exists.

Do not improvise around a failed gate. The output of a failure is the exact failure evidence, not a weaker candidate.

## Cleanup after evidence is safely retained

The dedicated outer worktree can be removed after the retained candidate and required private evidence are safely preserved:

```bash
cd "$NEMBRA_REPO"
/usr/bin/git worktree remove --force "$FIELD_SOURCE"
/bin/rmdir "$FIELD_PARENT" 2>/dev/null || true
```

Removing the source worktree does not authorize or invalidate the retained candidate. The retained candidate's own exact provenance/evidence remains authoritative for the next gate.

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO UNTIL THE EXACT SIGNED CANDIDATE, CROSS-CHECK, INSTALL/RUNTIME RENDEZVOUS, FRESH PREFLIGHT, AND HARDENED FINAL GO RECORD ARE ALL ACCEPTED.**