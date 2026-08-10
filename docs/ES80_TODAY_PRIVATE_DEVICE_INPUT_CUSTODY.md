# ES80 TODAY Private Intended-Device Input Custody — V14

Status: **PRIVATE OPERATOR HANDOFF HARDENING — NON-AUTHORIZING. PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

Feature: Nembra Capture / first physical ES80 truth.

Frozen Capture product subject: `a0f4a33451f61411d6e0541f2e70edea5438342d`.

This helper hardens operator-side custody of the private intended-device identifier without changing the frozen Capture app, Bluetooth behavior, signing authority, field authorization, telemetry semantics, or the accepted producer.

## Why this helper exists

The earlier shell example correctly rejected symlinked private directories and existing final files and used Bash `noclobber`. That protects the final filename from ordinary replacement, but shell redirection still resolves the parent pathname at write time. A same-UID local actor could rename/retarget `.nembra-private` after the operator entered the secret but before the redirection opened the final file. The later accepted preflight would fail closed, but the secret could already have been written under the wrong directory subject.

`scripts/ci/es80_today_private_device_input.py` removes that write-time pathname authority and closes the accepted input/cleanup failure paths:

- opens every private-directory component with `O_DIRECTORY|O_NOFOLLOW`;
- creates only the final private directory when absent and requires exact mode `0700` plus current-user ownership;
- rejects a private path that traverses the supplied Nembra source repository;
- rejects an already-occupied final target before acquiring the private identifier while retaining `O_EXCL` as the race authority if a target appears after that precheck;
- converts `getpass.GetPassWarning` and `EOFError` into the secret-free `secure-terminal-input-unavailable` blocker rather than accepting echoed or incomplete terminal input;
- creates the final file relative to the pinned directory descriptor with `O_CREAT|O_EXCL|O_NOFOLLOW` and mode `0600`;
- validates that newly opened subject as a fresh regular current-user mode-`0600` single-link zero-length file before any secret byte is written;
- writes and `fsync`s through the retained file descriptor;
- reopens the full pathname after creation and requires the same directory device/inode and the same final file identity plus exact byte readback;
- handles ordinary failures and terminal aborts under the same cleanup boundary;
- first attempts to durably scrub the exact still-open inode with `ftruncate(0)`, `fsync`, and a size-zero proof, so a moved pathname or added hard link cannot preserve secret bytes merely by defeating unlink;
- uses descriptor-relative unlink only when the final pathname still names that same inode, the open inode is still single-link before unlink, and the open inode proves zero links after the directory is fsynced;
- surfaces the secret-free blocker `private-intended-device-cleanup-failed` instead of silently claiming cleanup when neither durable erasure route can be proven;
- never places the raw identifier in argv, environment variables, stdout, filenames, GitHub, or retained candidate artifacts.

This is private-input custody only. A successful helper invocation does not mean the signed candidate is accepted and does not grant permission to scan.

## Frozen-source boundary

The exact Capture field source `a0f4…` is intentionally frozen and therefore does **not** contain this later operator helper. Do not copy a moving `main` helper into `FIELD_SOURCE`, do not commit tooling into the frozen worktree, and do not substitute a newer app source SHA merely to gain the helper.

The helper must be materialized from a separate trusted local Nembra tooling repository exactly like the accepted external pre-signing helper. The accepted helper identity is:

- helper source commit: `af75ffa6dc4409a21822295428e4eeb922ac3d16`;
- helper path: `scripts/ci/es80_today_private_device_input.py`;
- helper Git blob: `50b12675a57fd2f570d833cfcdbfd7be59f52ca4`.

These bytes remain non-authorizing. They are the durable default-branch helper subject consumed by the signed-field handoff; physical Experiment One remains NO-GO.

## Operator materialization and use

Start with the exact frozen outer `FIELD_SOURCE` and a separate tooling repository containing the accepted helper commit. Materialize and verify the helper outside both the frozen source and the retained candidate directory:

```bash
set -euo pipefail
umask 077

PRIVATE_INPUT_HELPER_COMMIT='af75ffa6dc4409a21822295428e4eeb922ac3d16'
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

The helper prompts privately with `getpass`; do not pass the raw UDID on the command line. If secure terminal input is unavailable, the final path already exists, any custody check fails, or a failed acquisition cannot prove durable erasure, preserve the exact blocker and stop before signing. Do not delete or overwrite an existing final path merely to satisfy the helper.

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

It proves at minimum:

1. exact `0600` regular single-link creation under an exact `0700` private directory;
2. an already-occupied final target is rejected before the secret provider runs, while a target appearing after the precheck is still caught by exclusive creation and never clobbered;
3. symlinked ancestors fail before the secret provider is called;
4. repository-contained private paths fail before secret acquisition;
5. parent-path retarget after creation fails closed without treating the replacement pathname as the created subject;
6. partial-write and file-`fsync` failures do not retain secret-bearing bytes after cleanup;
7. failed pathname unlink still leaves the exact open inode durably scrubbed;
8. hard-link/path-retarget cleanup cannot preserve the secret merely by making pathname unlink unsafe;
9. terminal aborts use the same secret-erasure boundary before the original abort propagates;
10. `getpass` echo-fallback warning and EOF input fail closed without yielding a usable private identifier;
11. surrounding whitespace/newline is rejected and no final file is created.

The exact accepted helper blob is `50b12675a57fd2f570d833cfcdbfd7be59f52ca4`; the exact accepted regression blob on `af75ffa6dc4409a21822295428e4eeb922ac3d16` is `cf56956207d0e7838ec8c9638b271f340861ae59`.

## Truth boundary

This helper establishes no AOVOPRO ES80 identity, GATT/Tuya/DP meaning, speed/battery/current/power telemetry, command acknowledgement, scooter write authority, signed-field acceptance, device install proof, runtime provenance, or physical field authorization.

**PHYSICAL ES80 EXPERIMENT ONE REMAINS NO-GO / DO NOT SCAN / DO NOT RUN UNTIL THE EXACT SIGNED CANDIDATE, INDEPENDENT CROSS-CHECK, RETAINED-IPA INSTALL/RUNTIME RENDEZVOUS, FRESH PREFLIGHT, AND HARDENED FINAL GO RECORD ARE ALL ACCEPTED.**
