# ES80 TODAY Private Intended-Device Input Custody — V14

Status: **PRIVATE OPERATOR HANDOFF HARDENING — NON-AUTHORIZING. PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

Feature: Nembra Capture / first physical ES80 truth.

Frozen Capture product subject: `a0f4a33451f61411d6e0541f2e70edea5438342d`.

This guide covers only custody of the private intended-device identifier used by the signed Research Field Build handoff. It changes no frozen Capture app, Bluetooth behavior, signing authority, telemetry semantics, scooter capability, or physical authorization.

## Accepted helper subject

Current accepted private-input helper provenance:

- merged helper commit: `b479d851a54437ef394a4901c69db2d829d280e4`;
- helper path: `scripts/ci/es80_today_private_device_input.py`;
- helper Git blob: `62b719e8d9afb34da6d35d696e80edf926442696`;
- exact tested predecessor head carrying the same helper blob: `90d3578a1d39a1d019000583a712306b67786acf`;
- focused `Capture TODAY Field Candidate Preflight QA`: run `31350094260`, job `93339137927` — terminal success;
- physical authorization: never granted by this helper.

Do not materialize the original `05ce6d9a20487ab34aa31c5b6456910ed2ed438f` / `9a9f7f724ceaf895e52d6d443d326043f97645c8` helper for the current handoff. Those bytes are superseded.

## Custody contract

The accepted helper removes shell-pathname authority from secret acquisition:

- every private-directory component is opened with descriptor-relative no-follow directory semantics;
- an occupied final target is rejected before the secret provider is called;
- the final file is created relative to the pinned directory descriptor with `O_CREAT|O_EXCL|O_NOFOLLOW` and mode `0600`;
- the freshly created subject is validated before any private identifier byte is written;
- secure input fails closed if terminal echo cannot be disabled or input reaches EOF;
- exact directory/file identity, owner, mode, link count, size, and readback are checked before success;
- parent-path retargeting cannot convert a different pathname subject into accepted evidence;
- after secret bytes may exist, failure cleanup is nondestructive to mutable pathnames: the helper never pathname-unlinks; it truncates, fsyncs, and proves zero length only through the exact still-open created inode;
- hard-link aliases to that exact inode are scrubbed by the same descriptor operation;
- if durable zero-length proof cannot be established, the helper surfaces `private-intended-device-cleanup-failed` rather than hiding unresolved secret custody;
- raw identifier bytes never belong in argv, environment variables, stdout, filenames, GitHub, screenshots, or retained candidate artifacts.

A failed attempt may legitimately leave a mode-`0600` zero-length spent subject. Preserve it. Do not delete or reuse it merely to make the next attempt pass.

## Frozen-source boundary

The frozen field source `a0f4…` intentionally predates this helper. Do not copy current tooling into `FIELD_SOURCE` and do not substitute a newer app SHA merely to gain the helper.

Materialize the exact accepted helper from a separate trusted local Nembra tooling repository. The tooling checkout and helper material stay outside both `FIELD_SOURCE` and the retained candidate directory.

## Operator materialization and fresh filename binding

Every attempt uses one fresh **non-secret** filename. The same `UDID_FILENAME` must both derive `UDID_FILE` and be passed to the helper through `--filename`; changing only a shell path after a spent attempt is not sufficient.

```bash
set -euo pipefail
umask 077

PRIVATE_INPUT_HELPER_COMMIT='b479d851a54437ef394a4901c69db2d829d280e4'
PRIVATE_INPUT_HELPER_BLOB='62b719e8d9afb34da6d35d696e80edf926442696'
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
UDID_FILENAME="es80-intended-device-$(/usr/bin/uuidgen).udid"
UDID_FILE="$PRIVATE_DIR/$UDID_FILENAME"

/usr/bin/python3 -I "$PRIVATE_INPUT_HELPER" \
  --private-directory "$PRIVATE_DIR" \
  --source-repo "$FIELD_SOURCE" \
  --filename "$UDID_FILENAME"

test -f "$UDID_FILE" && test ! -L "$UDID_FILE"
test "$(/usr/bin/stat -f '%Lp' "$UDID_FILE")" = '600'
NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE="$UDID_FILE"
```

The helper prompts privately with `getpass`; do not pass the raw UDID on the command line. If the helper reports `NOT_READY`, stop and preserve the exact blocker. If a zero-length spent subject remains, rerun the filename-generation and helper steps so `/usr/bin/uuidgen` creates a fresh non-secret `UDID_FILENAME`; never pre-delete the spent subject.

Keep `PRIVATE_INPUT_HELPER_DIR` outside `ARTIFACTS_DIR`. Do not mutate the producer's retained candidate shape with operator tooling or auxiliary files.

After creation, continue only through `docs/ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md` and its accepted external pre-signing preflight. That preflight must still report:

- `READY_TO_INVOKE_SIGNED_FIELD_PRODUCER`;
- authority `operator-pre-signing-readiness-not-field-authorization`;
- `physicalExperimentAuthorization = not-granted`;
- exact frozen source `a0f4a33451f61411d6e0541f2e70edea5438342d`.

Candidate production is still followed by independent retained-candidate cross-check, exact retained-IPA install, Home-Screen runtime rendezvous, fresh preflight, and hardened Final GO.

## Regression contract

Focused adversarial coverage in `scripts/ci/tests/test_es80_today_private_device_input.py` must continue to prove the accepted helper's descriptor-bound creation, pre-prompt occupied-target refusal, secure terminal handling, exact successful file contract, retarget resistance, failure/terminal-abort scrub behavior, hard-link behavior, and secret-free cleanup blocker.

Operator-handoff regression must additionally prove that the current helper commit/blob is used consistently, that `UDID_FILE` is derived from the same `UDID_FILENAME` passed through `--filename`, and that frozen-source checks are explicitly scoped to `FIELD_SOURCE` rather than the tooling checkout's current working directory.

## Truth boundary

This helper establishes no AOVOPRO ES80 identity, GATT/Tuya/DP meaning, speed/battery/current/power telemetry, command acknowledgement, scooter write authority, signed-field acceptance, device install proof, runtime provenance, or physical field authorization.

**PHYSICAL ES80 EXPERIMENT ONE REMAINS NO-GO / DO NOT SCAN / DO NOT RUN UNTIL THE EXACT SIGNED CANDIDATE, INDEPENDENT CROSS-CHECK, RETAINED-IPA INSTALL/RUNTIME RENDEZVOUS, FRESH PREFLIGHT, AND HARDENED FINAL GO RECORD ARE ALL ACCEPTED.**
