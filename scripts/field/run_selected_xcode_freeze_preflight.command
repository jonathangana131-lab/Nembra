#!/bin/bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

# Validation-only private field-Mac preflight for selected-Xcode custody.
#
# This command never builds/signs/installs/launches an app, enumerates devices,
# uses Bluetooth/Tuya, or touches the scooter. It executes only the exact accepted
# selected-Xcode launcher/helper/liveness-guard Git objects, requires the launcher
# to revoke reusable sudo authority before freeze publication, runs harmless frozen
# tool identity/help commands, then arms a root verifier that seals the final receipt
# only after this exact field shell exits and the launcher's root janitor removes the
# exact admitted freeze namespace.

SCRIPT_PATH="scripts/field/run_selected_xcode_freeze_preflight.command"
LAUNCHER_PATH="scripts/ci/capture_selected_xcode_freeze_launcher.py"
HELPER_PATH="scripts/ci/capture_selected_xcode_freeze.py"
GUARD_PATH="scripts/ci/capture_selected_xcode_process_liveness_guard.py"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

[[ "$(uname -s)" == "Darwin" ]] || fail "Selected-Xcode field preflight requires macOS."
[[ "${EUID:-$(id -u)}" -ne 0 ]] || fail "Run as the real field user, not root."
[[ "$#" == 2 ]] || fail "Usage: $0 <absolute-repository-root> <40-hex-accepted-source-sha>"

REPOSITORY_ROOT="$1"
SOURCE_SHA="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
[[ "$REPOSITORY_ROOT" == /* ]] || fail "Repository root must be absolute."
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "Accepted source SHA must be exactly 40 lowercase hex characters."
[[ -d "$REPOSITORY_ROOT/.git" && ! -L "$REPOSITORY_ROOT/.git" ]] || fail "Repository root must contain one real .git directory."
REPOSITORY_ABS="$(cd "$REPOSITORY_ROOT" && pwd -P)"
[[ "$REPOSITORY_ABS" == "$REPOSITORY_ROOT" ]] || fail "Repository root must already be canonical."
GIT_DIR_ABS="$(cd "$REPOSITORY_ROOT/.git" && pwd -P)"
[[ "$GIT_DIR_ABS" == "$REPOSITORY_ROOT/.git" ]] || fail "Repository .git directory must be canonical and real."

GIT=(/usr/bin/git --git-dir="$GIT_DIR_ABS" --work-tree="$REPOSITORY_ROOT" -c core.hooksPath=/dev/null)
GIT_ENV=(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_OPTIONAL_LOCKS=0)

HEAD_SHA="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse HEAD 2>/dev/null | tr '[:upper:]' '[:lower:]')" || fail "Could not resolve repository HEAD."
[[ "$HEAD_SHA" == "$SOURCE_SHA" ]] || fail "Repository HEAD is not the exact accepted selected-Xcode preflight source."
[[ -z "$("${GIT_ENV[@]}" "${GIT[@]}" status --porcelain=v1 --untracked-files=all)" ]] || fail "Accepted-source checkout is dirty."

blob_for() {
    "${GIT_ENV[@]}" "${GIT[@]}" rev-parse "$SOURCE_SHA:$1" 2>/dev/null
}
base64_for_blob() {
    "${GIT_ENV[@]}" "${GIT[@]}" cat-file blob "$1" | /usr/bin/base64 | /usr/bin/tr -d '\r\n'
}

SCRIPT_BLOB="$(blob_for "$SCRIPT_PATH")" || fail "Field preflight is absent from accepted source."
LAUNCHER_BLOB="$(blob_for "$LAUNCHER_PATH")" || fail "Selected-Xcode launcher is absent from accepted source."
HELPER_BLOB="$(blob_for "$HELPER_PATH")" || fail "Selected-Xcode helper is absent from accepted source."
GUARD_BLOB="$(blob_for "$GUARD_PATH")" || fail "Selected-Xcode liveness guard is absent from accepted source."
for blob in "$SCRIPT_BLOB" "$LAUNCHER_BLOB" "$HELPER_BLOB" "$GUARD_BLOB"; do
    [[ "$blob" =~ ^[0-9a-f]{40}$ ]] || fail "Accepted Git blob identity is malformed."
done

EXECUTING_SCRIPT="$0"
if [[ "$EXECUTING_SCRIPT" != /* ]]; then
    EXECUTING_SCRIPT="$(pwd -P)/$EXECUTING_SCRIPT"
fi
CURRENT_SCRIPT_BLOB="$("${GIT_ENV[@]}" "${GIT[@]}" hash-object "$EXECUTING_SCRIPT" 2>/dev/null)" || fail "Could not fingerprint executing preflight bytes."
[[ "$CURRENT_SCRIPT_BLOB" == "$SCRIPT_BLOB" ]] || fail "Executing field-preflight bytes do not match the accepted Git object."

# The production launcher requires a revocable authenticated sudo timestamp and
# explicitly rejects NOPASSWD/exempt policy. The preflight must enter root once;
# launcher policy inspection + invalidation is the authoritative isolation gate.
/usr/bin/sudo -n /usr/bin/true >/dev/null 2>&1 || fail "Authenticate sudo once in this field shell, then rerun immediately. Do not configure passwordless sudo."

FIELD_PID="$$"
FIELD_UID="$(/usr/bin/id -u)"
FIELD_GID="$(/usr/bin/id -g)"
[[ "$FIELD_UID" -gt 0 && "$FIELD_GID" -gt 0 ]] || fail "Field identity must be non-root."
PS_UID="$(/bin/ps -o uid= -p "$FIELD_PID" | /usr/bin/tr -d '[:space:]')"
[[ "$PS_UID" == "$FIELD_UID" ]] || fail "Preflight shell PID is not owned by the active field UID."

LAUNCHER_B64="$(base64_for_blob "$LAUNCHER_BLOB")"
HELPER_B64="$(base64_for_blob "$HELPER_BLOB")"
GUARD_B64="$(base64_for_blob "$GUARD_BLOB")"
[[ -n "$LAUNCHER_B64" && -n "$HELPER_B64" && -n "$GUARD_B64" ]] || fail "Accepted selected-Xcode objects could not be transported."

ROOT_PROGRAM="$(/bin/cat <<'PY'
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import tempfile
import time

launcher_b64, launcher_blob, helper_b64, helper_blob, guard_b64, guard_blob, field_pid_raw, source_sha, script_blob = sys.argv[1:]

if re.fullmatch(r'[0-9a-f]{40}', source_sha) is None or re.fullmatch(r'[0-9a-f]{40}', script_blob) is None:
    raise SystemExit('accepted source/script identity is malformed')
try:
    field_pid = int(field_pid_raw)
except ValueError as error:
    raise SystemExit('field PID is malformed') from error
if field_pid <= 1:
    raise SystemExit('field PID is invalid')

def verified(encoded: str, expected: str, label: str) -> bytes:
    if re.fullmatch(r'[0-9a-f]{40}', expected) is None:
        raise SystemExit(f'{label} blob identity is malformed')
    raw = base64.b64decode(encoded, validate=True)
    actual = hashlib.sha1(b'blob ' + str(len(raw)).encode('ascii') + b'\0' + raw).hexdigest()
    if actual != expected:
        raise SystemExit(f'{label} failed root Git-blob identity')
    return raw

launcher_raw = verified(launcher_b64, launcher_blob, 'launcher')
helper_raw = verified(helper_b64, helper_blob, 'helper')
guard_raw = verified(guard_b64, guard_blob, 'liveness guard')

launcher = {'__name__':'nembra_selected_xcode_field_preflight_launcher','__file__':'<accepted-launcher>'}
exec(compile(launcher_raw, '<accepted-launcher>', 'exec', dont_inherit=True), launcher)
guard = {'__name__':'nembra_selected_xcode_field_preflight_guard','__file__':'<accepted-liveness-guard>'}
exec(compile(guard_raw, '<accepted-liveness-guard>', 'exec', dont_inherit=True), guard)
install = guard.get('install_into_launcher')
run = launcher.get('run')
identify = launcher.get('_invoking_field_identity')
field_start_identity = launcher.get('_field_start_identity')
same_field = launcher.get('_same_field_process')
if not callable(install) or not callable(run) or not callable(identify) or not callable(field_start_identity) or not callable(same_field):
    raise SystemExit('accepted launcher/guard callable contract is incomplete')
install(launcher)
# Re-read after patch installation.
same_field = launcher.get('_same_field_process')
if not callable(same_field):
    raise SystemExit('fail-closed exact-process liveness guard was not installed')

field_user, field_uid, field_gid, field_home, field_groups = identify()
field_start = field_start_identity(field_pid, field_uid)

# The launcher itself re-verifies helper Git identity, rejects passwordless sudo,
# invalidates the invoking field timestamp, recovers only classified stale freezes,
# creates the COW/root/no-ACL Apple-signed subject, proves field mutation denial,
# and starts its exact-field-process root janitor.
namespace, developer, tools, janitor_pid = run(field_pid, source_sha, helper_b64, helper_blob)
namespace = Path(namespace)
developer = Path(developer)

lifecycle = namespace / '.nembra-freeze-lifecycle.json'
metadata = os.lstat(lifecycle)
if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
    raise SystemExit('selected-Xcode lifecycle receipt is not one root regular file')
if metadata.st_uid != 0 or metadata.st_gid != 0 or stat.S_IMODE(metadata.st_mode) != 0o400:
    raise SystemExit('selected-Xcode lifecycle receipt lost root:wheel 0400 custody')

xcodebuild = Path(tools['xcodebuild'])
xctrace = Path(tools['xctrace'])
devicectl = Path(tools['devicectl'])
for tool in (xcodebuild, xctrace, devicectl):
    if not tool.is_absolute() or developer not in tool.parents or not os.access(tool, os.X_OK):
        raise SystemExit(f'frozen selected tool escaped admitted developer tree: {tool}')

closed_env = {
    'PATH':'/usr/bin:/bin:/usr/sbin:/sbin',
    'HOME':field_home,
    'USER':field_user,
    'LOGNAME':field_user,
    'TMPDIR':'/tmp',
    'LANG':'C',
    'LC_ALL':'C',
    'DEVELOPER_DIR':str(developer),
}
extra_groups = sorted({int(value) for value in field_groups if int(value) != field_gid})
creds = {'user':field_uid, 'group':field_gid, 'extra_groups':extra_groups}

def field_tool(argv):
    return subprocess.run(
        [str(value) for value in argv],
        env=closed_env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        **creds,
    )

version = field_tool([xcodebuild, '-version'])
if version.returncode != 0:
    raise SystemExit('frozen xcodebuild -version failed under exact field credentials')
first = version.stdout.splitlines()[0] if version.stdout.splitlines() else ''
if first != 'Xcode 27' and not first.startswith('Xcode 27.'):
    raise SystemExit(f'frozen selected toolchain is not Xcode 27: {first or "<empty>"}')
trace = field_tool([xctrace, 'version'])
if trace.returncode != 0:
    raise SystemExit('frozen xctrace version failed under exact field credentials')
device_help = field_tool([devicectl, 'help'])
if device_help.returncode != 0:
    raise SystemExit('frozen devicectl help failed under exact field credentials')

receipt_dir = Path(tempfile.mkdtemp(prefix='nembra-selected-xcode-field-preflight.', dir='/private/tmp'))
os.chown(receipt_dir, 0, 0)
os.chmod(receipt_dir, 0o755)
receipt_path = receipt_dir / 'receipt.json'

base_receipt = {
    'schema':1,
    'sourceSHA':source_sha,
    'scriptGitBlob':script_blob,
    'launcherGitBlob':launcher_blob,
    'helperGitBlob':helper_blob,
    'livenessGuardGitBlob':guard_blob,
    'fieldUID':field_uid,
    'fieldPID':field_pid,
    'fieldStartIdentity':field_start,
    'freezeNamespace':str(namespace),
    'frozenDeveloper':str(developer),
    'xcodebuildVersion':first,
    'xctraceVersionProbeSucceeded':True,
    'devicectlHelpProbeSucceeded':True,
    'deviceDiscoveryPerformed':False,
    'deviceInstallPerformed':False,
    'appLaunchPerformed':False,
    'bluetoothUsed':False,
    'privateTuyaInputsUsed':False,
    'physicalAuthorityCreated':False,
}

verifier = os.fork()
if verifier == 0:
    try:
        os.setsid()
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
        devnull = os.open('/dev/null', os.O_RDWR)
        try:
            for descriptor in (0,1,2):
                os.dup2(devnull, descriptor)
        finally:
            if devnull > 2:
                os.close(devnull)

        # Wait for the exact originating field shell to disappear. Ambiguous
        # liveness remains live because the installed guard is fail-closed.
        while same_field(field_pid, field_uid, field_start):
            time.sleep(0.25)

        deadline = time.monotonic() + 180.0
        cleanup_observed = not namespace.exists()
        while not cleanup_observed and time.monotonic() < deadline:
            time.sleep(0.25)
            cleanup_observed = not namespace.exists()

        receipt = dict(base_receipt)
        receipt.update({
            'fieldProcessRetired':True,
            'janitorCleanupObserved':cleanup_observed,
            'accepted':cleanup_observed,
            'physicalAuthorityCreated':False,
        })
        raw = (json.dumps(receipt, sort_keys=True, separators=(',',':')) + '\n').encode('utf-8')
        fd = os.open(receipt_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o444)
        try:
            os.write(fd, raw)
            os.fsync(fd)
        finally:
            os.close(fd)
        os.chown(receipt_path, 0, 0)
        os.chmod(receipt_path, 0o444)
        directory_fd = os.open(receipt_dir, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        os._exit(0)

armed = {
    'schema':1,
    'sourceSHA':source_sha,
    'receiptPath':str(receipt_path),
    'freezeNamespace':str(namespace),
    'janitorPID':int(janitor_pid),
    'postExitVerifierPID':int(verifier),
    'sudoInvalidationOwnedByAcceptedLauncher':True,
    'deviceDiscoveryPerformed':False,
    'deviceInstallPerformed':False,
    'appLaunchPerformed':False,
    'bluetoothUsed':False,
    'privateTuyaInputsUsed':False,
    'physicalAuthorityCreated':False,
}
print(json.dumps(armed, sort_keys=True, separators=(',',':')))
PY
)"

ARMED_JSON="$(/usr/bin/sudo -n /usr/bin/python3 -B -I -c "$ROOT_PROGRAM" \
    "$LAUNCHER_B64" "$LAUNCHER_BLOB" \
    "$HELPER_B64" "$HELPER_BLOB" \
    "$GUARD_B64" "$GUARD_BLOB" \
    "$FIELD_PID" "$SOURCE_SHA" "$SCRIPT_BLOB")" || fail "Accepted selected-Xcode field preflight failed before arming its post-exit receipt."
unset ROOT_PROGRAM LAUNCHER_B64 HELPER_B64 GUARD_B64

# The accepted launcher must have revoked the authenticated timestamp, and its
# policy oracle must have rejected any policy that would make -n work anyway.
if /usr/bin/sudo -n /usr/bin/true >/dev/null 2>&1; then
    fail "Reusable sudo authority survived selected-Xcode preflight publication."
fi
if /usr/bin/sudo -n -l >/dev/null 2>&1; then
    fail "Noninteractive sudo policy remains available after selected-Xcode preflight publication."
fi

/usr/bin/python3 -B -I - "$ARMED_JSON" "$SOURCE_SHA" <<'PY'
import json,sys
payload=json.loads(sys.argv[1])
assert payload['schema'] == 1
assert payload['sourceSHA'] == sys.argv[2]
assert payload['receiptPath'].startswith('/private/tmp/nembra-selected-xcode-field-preflight.')
assert payload['receiptPath'].endswith('/receipt.json')
assert payload['freezeNamespace'].startswith('/Library/NembraSelectedXcodeFreeze.')
assert payload['janitorPID'] > 1
assert payload['postExitVerifierPID'] > 1
assert payload['sudoInvalidationOwnedByAcceptedLauncher'] is True
assert payload['deviceDiscoveryPerformed'] is False
assert payload['deviceInstallPerformed'] is False
assert payload['appLaunchPerformed'] is False
assert payload['bluetoothUsed'] is False
assert payload['privateTuyaInputsUsed'] is False
assert payload['physicalAuthorityCreated'] is False
print('CAPTURE_SELECTED_XCODE_FIELD_PREFLIGHT_ARMED')
print('FINAL_RECEIPT=' + payload['receiptPath'])
print('Exit this exact field shell normally. The root verifier seals the final receipt only after the janitor removes the exact freeze namespace.')
PY

# Success here means only that the validation was armed correctly. The final receipt
# is authoritative for post-exit janitor cleanup and must contain accepted=true.
exit 0
