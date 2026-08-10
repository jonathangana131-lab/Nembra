# ES80 TODAY Private Intended-Device Input Custody — V14

Status: **PRIVATE OPERATOR HANDOFF HARDENING — NON-AUTHORIZING. PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

Feature: Nembra Capture / first physical ES80 truth.

Frozen Capture product subject: `a0f4a33451f61411d6e0541f2e70edea5438342d`.

This helper closes one operator-side custody race without changing the frozen Capture app, Bluetooth behavior, signing authority, field authorization, telemetry semantics, or the accepted producer.

## Why this helper exists

The earlier shell example correctly rejected symlinked private directories and existing final files and used Bash `noclobber`. That protects the final filename from ordinary replacement, but shell redirection still resolves the parent pathname at write time. A same-UID local actor could rename/retarget `.nembra-private` after the operator entered the secret but before the redirection opened the final file. The later accepted preflight would fail closed, but the secret could already have been written under the wrong directory subject.

`scripts/ci/es80_today_private_device_input.py` removes that write-time pathname authority:

- opens every private-directory component with `O_DIRECTORY|O_NOFOLLOW`;
- creates only the final private directory when absent and requires exact mode `0700` plus current-user ownership;
- rejects a private path that traverses the supplied Nembra source repository;
- acquires the intended-device identifier only after directory admission;
- creates the final file relative to the pinned directory descriptor with `O_CREAT|O_EXCL|O_NOFOLLOW` and mode `0600`;
- writes and `fsync`s through the file descriptor;
- reopens the full pathname after creation and requires the same directory device/inode and the same file identity plus exact byte readback;
- if the pathname was retargeted, fails closed and removes only the file whose identity matches the file created under the original pinned directory;
- never places the raw identifier in argv, environment variables, stdout, filenames, GitHub, or retained candidate artifacts.

This is private-input custody only. A successful helper invocation does not mean the signed candidate is accepted and does not grant permission to scan.

## Frozen-source boundary

The exact Capture field source `a0f4…` is intentionally frozen and therefore does **not** contain this later operator helper. Do not copy a moving `main` helper into `FIELD_SOURCE`, do not commit tooling into the frozen worktree, and do not substitute a newer app source SHA merely to gain the helper.

The helper must be materialized from a separate trusted local Nembra tooling repository exactly like the already accepted external pre-signing helper. The current candidate helper identity is:

- helper source commit: `05ce6d9a20487ab34aa31c5b6456910ed2ed438f`;
- helper path: `scripts/ci/es80_today_private_device_input.py`;
- helper Git blob: `9a9f7f724ceaf895e52d6d443d326043f97645c8`.

These bytes remain non-authorizing. Before this helper is used for an actual field candidate, this PR/lineage itself must be accepted into the trusted handoff. Until then, keep following the currently accepted production gates and keep Experiment One NO-GO.

## Operator materialization and use after acceptance

Start with the exact frozen outer `FIELD_SOURCE` and a separate tooling repository containing the accepted helper commit. Materialize and verify the helper outside both the frozen source and the retained candidate directory:

```bash
set -euo pipefail
umask 077

PRIVATE_INPUT_HELPER_COMMIT='05ce6d9a20487ab34aa31c5b6456910ed2ed438f'
PRIVATE_INPUT_HELPER_BLOB='9a9f7f724ceaf895e52d6d443d326043f97645c8'
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

The helper prompts privately with `getpass`; do not pass the raw UDID on the command line. If the final path already exists, preserve it and choose a fresh filename/path rather than deleting or overwriting it just to satisfy the helper.

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
2. pre-existing final targets are never clobbered;
3. symlinked ancestors fail before the secret provider is called;
4. repository-contained private paths fail before secret acquisition;
5. a parent pathname retarget after file creation fails closed and cleans the original created file rather than touching the replacement directory;
6. surrounding whitespace/newline is rejected and no final file is created.

The exact tested candidate helper blob is `9a9f7f724ceaf895e52d6d443d326043f97645c8`; the exact tested regression blob is `f1aeb6fa6336481222626d3b6b01137ba338b346`.

## Truth boundary

This helper establishes no AOVOPRO ES80 identity, GATT/Tuya/DP meaning, speed/battery/current/power telemetry, command acknowledgement, scooter write authority, signed-field acceptance, device install proof, runtime provenance, or physical field authorization.

**PHYSICAL ES80 EXPERIMENT ONE REMAINS NO-GO / DO NOT SCAN / DO NOT RUN UNTIL THE EXACT SIGNED CANDIDATE, INDEPENDENT CROSS-CHECK, RETAINED-IPA INSTALL/RUNTIME RENDEZVOUS, FRESH PREFLIGHT, AND HARDENED FINAL GO RECORD ARE ALL ACCEPTED.**
