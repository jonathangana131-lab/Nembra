# ES80 TODAY Private Intended-Device Input Custody — V14

Status: **PRIVATE OPERATOR HANDOFF HARDENING — NON-AUTHORIZING. PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

Feature: Nembra Capture / first physical ES80 truth.

Frozen Capture product subject: `a0f4a33451f61411d6e0541f2e70edea5438342d`.

This helper closes operator-side private-input custody races without changing the frozen Capture app, Bluetooth behavior, signing authority, field authorization, telemetry semantics, or the accepted producer.

## Why this helper exists

The earlier shell example correctly rejected symlinked private directories and existing final files and used Bash `noclobber`. That protects the final filename from ordinary replacement, but shell redirection still resolves the parent pathname at write time. A same-UID local actor could rename/retarget `.nembra-private` after the operator entered the secret but before the redirection opened the final file. The later accepted preflight would fail closed, but the secret could already have been written under the wrong directory subject.

`scripts/ci/es80_today_private_device_input.py` removes that write-time pathname authority and now preserves the full accepted failure-erasure and pre-prompt contract:

- opens every private-directory component with `O_DIRECTORY|O_NOFOLLOW`;
- creates only the final private directory when absent and requires exact mode `0700` plus current-user ownership;
- rejects a private path that traverses the supplied Nembra source repository;
- rejects an already-occupied final target **before** the secret provider is called;
- treats EOF or unavailable secure terminal input as a fail-closed `secure-terminal-input-unavailable` condition without creating output;
- creates the final file relative to the pinned directory descriptor with `O_CREAT|O_EXCL|O_NOFOLLOW` and mode `0600`, so a target racing into existence after the precheck still cannot be clobbered;
- writes and `fsync`s through the exact file descriptor;
- reopens the full pathname after creation and requires the same directory device/inode and the same file identity plus exact byte readback;
- on acquisition failure, first scrubs the exact still-open inode with `ftruncate(0)` + file `fsync` and proves size zero;
- accepts pathname unlink as a fallback only when the descriptor-relative name still identifies the exact inode, the inode remains single-linked immediately before unlink, directory `fsync` succeeds, and the open inode proves `st_nlink == 0` afterward;
- if neither durable erasure route can be proven, surfaces a secret-free `private-intended-device-cleanup-failed` blocker instead of pretending cleanup succeeded;
- never places the raw identifier in argv, environment variables, stdout, filenames, GitHub, or retained candidate artifacts.

This is private-input custody only. A successful helper invocation does not mean the signed candidate is accepted and does not grant permission to scan.

## Frozen-source boundary

The exact Capture field source `a0f4…` is intentionally frozen and therefore does **not** contain this later operator helper. Do not copy a moving `main` helper into `FIELD_SOURCE`, do not commit tooling into the frozen worktree, and do not substitute a newer app source SHA merely to gain the helper.

The helper must be materialized from a separate trusted local Nembra tooling repository exactly like the already accepted external pre-signing helper. The current accepted helper identity is:

- helper source commit: `91dda8ac05e937e5615312a487f7d78926b74949`;
- helper path: `scripts/ci/es80_today_private_device_input.py`;
- helper Git blob: `50b12675a57fd2f570d833cfcdbfd7be59f52ca4`;
- exact focused QA run: `31349898562` — terminal success;
- exact focused QA job: `93338620824` — terminal success;
- merged current-main lineage at acceptance handoff: `af75ffa6dc4409a21822295428e4eeb922ac3d16`.

That exact QA head combines the durable secret-erasure model with the occupied-target-before-secret guard and EOF fail-closed terminal contract. The merge onto `main` preserves the same helper bytes. These bytes remain non-authorizing.

Superseded helper identity retained only for audit history: commit `05ce6d9a20487ab34aa31c5b6456910ed2ed438f`, blob `9a9f7f724ceaf895e52d6d443d326043f97645c8`. **Do not materialize or invoke that superseded helper for the current TODAY handoff.**

## Operator materialization and use

Start with the exact frozen outer `FIELD_SOURCE` and a separate tooling repository containing the accepted helper commit. Materialize and verify the helper outside both the frozen source and the retained candidate directory:

```bash
set -euo pipefail
umask 077

PRIVATE_INPUT_HELPER_COMMIT='91dda8ac05e937e5615312a487f7d78926b74949'
PRIVATE_INPUT_HELPER_BLOB='50b12675a57fd2f570d833cfcdbfd7be59f52ca4'
TOOL_REPO='/absolute/path/to/a/local/Nembra/tooling-repository'
PRIVATE_INPUT_HELPER_DIR="$(/usr/bin/mktemp -d /tmp/nembra-es80-private-input.XXXXXX)"
PRIVATE_INPUT_HELPER="$PRIVATE_INPUT_HELPER_DIR/es80_today_private_device_input.py"

cd "$TOOL_REPO"
/usr/bin/git cat-file -e "$PRIVATE_INPUT_HELPER_COMMIT^{commit}"
test "$(/usr/bin/git rev-parse --verify "$PRIVATE_INPUT_HELPER_COMMIT:scripts/ci/es80_today_private_device_input.py")" = "$PRIVATE_INPUT_HELPER_BLOB"
/usr/bin/git show "$PRIVATE_INPUT_HELPER_COMMIT:scripts/ci/es80_today_private_device_input.py" > "$PRIVATE_INPUT_HELPER"
test "$(/usr/bin/git hash-object --no-filters -- "$PRIVATE_INPUT_HELPER")" = "$PRIVATE_INPUT_HELPER_BLOB"

HOME_PHYSICAL="$(cd -P -- "$HOME" && /bin/pwd -P)"
test -n "$HOME_PHYSICAL" && test "${HOME_PHYSICAL#/}" != "$HOME_PHYSICAL"
PRIVATE_DIR="$HOME_PHYSICAL/.nembra-private"
UDID_FILE="$PRIVATE_DIR/es80-intended-device.udid"

/usr/bin/python3 -I "$PRIVATE_INPUT_HELPER" \
  --private-directory "$PRIVATE_DIR" \
  --source-repo "$FIELD_SOURCE"

test -f "$UDID_FILE" && test ! -L "$UDID_FILE"
test "$(/usr/bin/stat -f '%Lp' "$UDID_FILE")" = '600'
NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE="$UDID_FILE"
```

The helper prompts privately with `getpass`; do not pass the raw UDID on the command line. If the final path already exists, the helper refuses **before** asking for the secret. Preserve that target and choose a fresh filename/path rather than deleting or overwriting it just to satisfy the helper. If secure terminal input is unavailable or reaches EOF, stop; do not substitute echoing stdin or shell redirection.

Keep `PRIVATE_INPUT_HELPER_DIR` outside `ARTIFACTS_DIR`. Do not mutate the producer's retained candidate shape with operator tooling or auxiliary files.

After creation, continue through the accepted external pre-signing preflight. The preflight must still report:

- `READY_TO_INVOKE_SIGNED_FIELD_PRODUCER`;
- authority `operator-pre-signing-readiness-not-field-authorization`;
- `physicalExperimentAuthorization = not-granted`;
- exact frozen source `a0f4a33451f61411d6e0541f2e70edea5438342d`.

Then and only then may the operator invoke the frozen TODAY signed-field producer. Candidate production is still followed by independent retained-IPA inspection/cross-check, exact retained install, Home-Screen runtime rendezvous, and hardened Final GO.

## Acceptance / regression contract

Focused adversarial coverage lives in:

`scripts/ci/tests/test_es80_today_private_device_input.py`

It must prove at minimum:

1. exact `0600` regular single-link creation under an exact `0700` private directory;
2. an existing final target is rejected before the secret provider runs and is never clobbered;
3. a target racing into existence after the precheck is still rejected by exclusive descriptor-relative creation;
4. symlinked ancestors fail before the secret provider is called;
5. repository-contained private paths fail before secret acquisition;
6. a parent pathname retarget after file creation fails closed and cleanup acts only on the exact created inode;
7. partial-write and fsync failures cannot return as cleanup-safe unless exact bytes are durably erased or exact single-link unlink is durably proven;
8. a hard-link race cannot preserve secret bytes while cleanup is called safe;
9. surrounding whitespace/newline/control characters are rejected;
10. secure-terminal echo fallback and EOF both fail closed without output creation or secret disclosure.

The exact accepted helper blob is `50b12675a57fd2f570d833cfcdbfd7be59f52ca4`; the exact accepted regression blob at `91dda8ac…` is `cf56956207d0e7838ec8c9638b271f340861ae59`. Exact focused QA is run `31349898562`, job `93338620824`, terminal success.

## Truth boundary

This helper establishes no AOVOPRO ES80 identity, GATT/Tuya/DP meaning, speed/battery/current/power telemetry, command acknowledgement, scooter write authority, signed-field acceptance, device install proof, runtime provenance, or physical field authorization.

**PHYSICAL ES80 EXPERIMENT ONE REMAINS NO-GO / DO NOT SCAN / DO NOT RUN UNTIL THE EXACT SIGNED CANDIDATE, INDEPENDENT CROSS-CHECK, RETAINED-IPA INSTALL/RUNTIME RENDEZVOUS, FRESH PREFLIGHT, AND HARDENED FINAL GO RECORD ARE ALL ACCEPTED.**
