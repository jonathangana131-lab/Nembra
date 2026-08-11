#!/bin/bash -p
set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset BASH_ENV ENV CDPATH || true
hash -r

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$ROOT"

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Run this on the Mac with Xcode and the intended iPhone connected."
[[ -x /usr/bin/xcodebuild ]] || die "Xcode command-line tools are not available."
[[ -x /usr/bin/xcrun ]] || die "xcrun is not available."
[[ -x /usr/bin/security ]] || die "macOS security tool is not available."
[[ -x /usr/bin/python3 ]] || die "System Python 3 is required for private intended-device admission."
[[ -x /usr/bin/plutil ]] || die "System plutil is required for exact built-app provenance verification."
[[ -x /usr/bin/codesign ]] || die "System codesign is required for effective signed-entitlement verification."
[[ -x /usr/bin/security ]] || die "System security is required for embedded provisioning-profile verification."

EXPECTED_SOURCE_SHA="${1:-${NEMBRA_CAPTURE_EXPECTED_SOURCE_SHA:-}}"
[[ "$EXPECTED_SOURCE_SHA" =~ ^[0-9A-Fa-f]{40}$ ]] || die "Pass the exact software-accepted Capture source SHA as the first argument (40 hex characters)."
EXPECTED_SOURCE_SHA="$(printf '%s' "$EXPECTED_SOURCE_SHA" | tr '[:upper:]' '[:lower:]')"

# Physical source authority is tied to this installer's real checkout, never to
# caller GIT_* selection or repository-local worktree redirection. Field-only
# ignored inputs remain available, but tracked source bytes must match the exact
# externally accepted commit through an independent raw-byte audit.
AUTHORITY_GIT_DIR="$ROOT/.git"
[[ -d "$AUTHORITY_GIT_DIR" && ! -L "$AUTHORITY_GIT_DIR" ]] || die "Accepted field checkout must contain one real .git directory."
for variable in ${!GIT_@}; do
    unset "$variable"
done
unset variable || true

run_authority_git() {
    /usr/bin/env -i \
        PATH=/usr/bin:/bin \
        HOME=/tmp \
        LANG=C \
        LC_ALL=C \
        GIT_DIR="$AUTHORITY_GIT_DIR" \
        GIT_WORK_TREE="$ROOT" \
        GIT_CONFIG_NOSYSTEM=1 \
        GIT_CONFIG_GLOBAL=/dev/null \
        GIT_NO_REPLACE_OBJECTS=1 \
        GIT_CONFIG_COUNT=7 \
        GIT_CONFIG_KEY_0=core.worktree \
        GIT_CONFIG_VALUE_0="$ROOT" \
        GIT_CONFIG_KEY_1=core.bare \
        GIT_CONFIG_VALUE_1=false \
        GIT_CONFIG_KEY_2=core.fsmonitor \
        GIT_CONFIG_VALUE_2=false \
        GIT_CONFIG_KEY_3=core.ignorestat \
        GIT_CONFIG_VALUE_3=false \
        GIT_CONFIG_KEY_4=core.filemode \
        GIT_CONFIG_VALUE_4=true \
        GIT_CONFIG_KEY_5=core.excludesFile \
        GIT_CONFIG_VALUE_5=/dev/null \
        GIT_CONFIG_KEY_6=core.sparseCheckout \
        GIT_CONFIG_VALUE_6=false \
        /usr/bin/git "$@"
}

SOURCE_SHA="$(run_authority_git rev-parse --verify 'HEAD^{commit}' | tr '[:upper:]' '[:lower:]')" || die "Could not resolve HEAD from the accepted field checkout."
[[ "$SOURCE_SHA" == "$EXPECTED_SOURCE_SHA" ]] || die "Current checkout $SOURCE_SHA does not match accepted Capture source $EXPECTED_SOURCE_SHA. Checkout the exact accepted SHA before building."

verify_accepted_checkout_source() {
    local context="${1:-Accepted Capture source changed.}"
    local authority_index tracked_status
    [[ "$(run_authority_git rev-parse --verify 'HEAD^{commit}' | tr '[:upper:]' '[:lower:]')" == "$SOURCE_SHA" ]] || die "$context Repository HEAD no longer matches the accepted source."

    authority_index="$(/usr/bin/mktemp -t nembra-capture-field-index)" || die "$context Could not allocate a fresh source-authority index."
    /bin/rm -f -- "$authority_index"
    if ! /usr/bin/env -i \
        PATH=/usr/bin:/bin HOME=/tmp LANG=C LC_ALL=C \
        GIT_DIR="$AUTHORITY_GIT_DIR" GIT_WORK_TREE="$ROOT" \
        GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 \
        GIT_INDEX_FILE="$authority_index" \
        GIT_CONFIG_COUNT=5 \
        GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0="$ROOT" \
        GIT_CONFIG_KEY_1=core.bare GIT_CONFIG_VALUE_1=false \
        GIT_CONFIG_KEY_2=core.fsmonitor GIT_CONFIG_VALUE_2=false \
        GIT_CONFIG_KEY_3=core.ignorestat GIT_CONFIG_VALUE_3=false \
        GIT_CONFIG_KEY_4=core.filemode GIT_CONFIG_VALUE_4=true \
        /usr/bin/git read-tree "$SOURCE_SHA"; then
        /bin/rm -f -- "$authority_index"
        die "$context Could not build a fresh accepted-source authority index."
    fi
    tracked_status="$(
        /usr/bin/env -i \
            PATH=/usr/bin:/bin HOME=/tmp LANG=C LC_ALL=C \
            GIT_DIR="$AUTHORITY_GIT_DIR" GIT_WORK_TREE="$ROOT" \
            GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 \
            GIT_INDEX_FILE="$authority_index" \
            GIT_CONFIG_COUNT=5 \
            GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0="$ROOT" \
            GIT_CONFIG_KEY_1=core.bare GIT_CONFIG_VALUE_1=false \
            GIT_CONFIG_KEY_2=core.fsmonitor GIT_CONFIG_VALUE_2=false \
            GIT_CONFIG_KEY_3=core.ignorestat GIT_CONFIG_VALUE_3=false \
            GIT_CONFIG_KEY_4=core.filemode GIT_CONFIG_VALUE_4=true \
            /usr/bin/git -c core.fsmonitor=false -c core.ignorestat=false -c core.filemode=true \
                status --porcelain=v1 --untracked-files=no
    )" || {
        /bin/rm -f -- "$authority_index"
        die "$context Fresh-index tracked-source verification failed."
    }
    /bin/rm -f -- "$authority_index"
    [[ -z "$tracked_status" ]] || die "$context Tracked source differs from the accepted commit."

    /usr/bin/env -i \
        PATH=/usr/bin:/bin HOME=/tmp LANG=C LC_ALL=C \
        NEMBRA_ROOT="$ROOT" NEMBRA_SOURCE_SHA="$SOURCE_SHA" \
        GIT_DIR="$AUTHORITY_GIT_DIR" GIT_WORK_TREE="$ROOT" \
        GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 \
        GIT_CONFIG_COUNT=2 \
        GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0="$ROOT" \
        GIT_CONFIG_KEY_1=core.bare GIT_CONFIG_VALUE_1=false \
        /usr/bin/python3 -I - <<'PY' || die "$context Raw accepted-source byte audit failed."
import hashlib
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess

root = Path(os.environ["NEMBRA_ROOT"])
source_sha = os.environ["NEMBRA_SOURCE_SHA"]
git_env = os.environ.copy()
tree = subprocess.check_output(
    ["/usr/bin/git", "ls-tree", "-r", "-z", source_sha],
    cwd=root,
    env=git_env,
)
tracked: set[str] = set()
checked = 0
for record in tree.split(b"\0"):
    if not record:
        continue
    metadata, relative_raw = record.split(b"\t", 1)
    mode, object_type, expected_oid = metadata.split(b" ", 2)
    if object_type != b"blob" or mode not in {b"100644", b"100755", b"120000"}:
        raise SystemExit("raw accepted checkout refuses unsupported tracked object")
    relative = os.fsdecode(relative_raw)
    parts = PurePosixPath(relative).parts
    if not parts or any(part in {"", ".", ".."} for part in parts):
        raise SystemExit("raw accepted checkout contains an unsafe tracked path")
    tracked.add(relative)
    current = root
    for component in parts[:-1]:
        current = current / component
        current_meta = os.lstat(current)
        if not stat.S_ISDIR(current_meta.st_mode) or stat.S_ISLNK(current_meta.st_mode):
            raise SystemExit("raw accepted checkout has symlink/non-directory ancestry: " + relative)
    path = root.joinpath(*parts)
    current_meta = os.lstat(path)
    if mode == b"120000":
        if not stat.S_ISLNK(current_meta.st_mode):
            raise SystemExit("raw accepted checkout expected symlink: " + relative)
        payload = os.readlink(path)
        if isinstance(payload, str):
            payload = os.fsencode(payload)
    else:
        if not stat.S_ISREG(current_meta.st_mode):
            raise SystemExit("raw accepted checkout expected regular file: " + relative)
        expected_executable = mode == b"100755"
        actual_executable = bool(current_meta.st_mode & 0o111)
        if actual_executable != expected_executable:
            raise SystemExit("raw accepted checkout executable mode mismatch: " + relative)
        payload = path.read_bytes()
    actual_oid = hashlib.sha1(
        b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    ).hexdigest().encode("ascii")
    if actual_oid != expected_oid:
        raise SystemExit("raw accepted checkout blob mismatch: " + relative)
    checked += 1

if checked == 0:
    raise SystemExit("raw accepted checkout audit found no tracked blobs")

field_input_directories = ("LocalSecrets", "Pods", "NembraCapture.xcworkspace")
for relative in field_input_directories:
    candidate = root / relative
    try:
        metadata = os.lstat(candidate)
    except OSError:
        raise SystemExit("required field-input directory is unavailable: " + relative)
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise SystemExit("field-input allowlist root must be one real directory: " + relative)
try:
    lock_metadata = os.lstat(root / "Podfile.lock")
except OSError:
    raise SystemExit("required field-input lockfile is unavailable: Podfile.lock")
if not stat.S_ISREG(lock_metadata.st_mode) or stat.S_ISLNK(lock_metadata.st_mode):
    raise SystemExit("field-input allowlist lockfile must be one real regular file: Podfile.lock")

allowed_roots = set(field_input_directories)
for current_raw, directories, files in os.walk(root, topdown=True, followlinks=False):
    current = Path(current_raw)
    current_relative = current.relative_to(root)
    if current_relative.parts and current_relative.parts[0] in allowed_roots:
        directories[:] = []
        continue
    if not current_relative.parts:
        directories[:] = [
            name for name in directories
            if name != ".git" and name not in allowed_roots
        ]
    for name in list(directories):
        candidate = current / name
        relative = candidate.relative_to(root).as_posix()
        if candidate.is_symlink():
            directories.remove(name)
            if relative not in tracked:
                raise SystemExit(
                    "untracked accepted-source path outside field-input allowlist: " + relative
                )
    for name in files:
        candidate = current / name
        relative = candidate.relative_to(root).as_posix()
        if relative in tracked or relative == "Podfile.lock":
            continue
        raise SystemExit(
            "untracked accepted-source path outside field-input allowlist: " + relative
        )
print(f"raw accepted checkout audit accepted {checked} tracked blobs")
PY
}

run_accepted_source_bash() {
    local relative_path="$1"
    [[ "$relative_path" != /* && "$relative_path" != *".."* ]] || die "Accepted Bash source path is invalid."
    if ! run_authority_git show "$SOURCE_SHA:$relative_path" |
        /bin/bash --noprofile --norc -p -c 'source /dev/stdin' "$ROOT/$relative_path"; then
        die "Accepted Bash source failed or could not be executed from exact Git authority: $relative_path"
    fi
}

verify_accepted_checkout_source "Current checkout is not the exact accepted Capture source."
say "Exact requested Capture source matched under isolated Git + raw-byte authority: $SOURCE_SHA"

# The intended-device identifier is private field-admission input, never product
# evidence. Reuse the canonical descriptor-bound reader so the private file is
# opened once with no-follow component checks and stable metadata/read custody.
# The raw identifier is captured in-process only; Nembra never prints it and
# never places it in a child process argv/environment.
unset NEMBRA_INTENDED_FIELD_DEVICE_UDID || true
: "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE to an absolute private mode-0600 file containing only the intended iPhone UDID.}"
: "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256:?Final GO must provide NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 as the accepted SHA-256 of the intended-device identifier.}"
[[ "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || die "NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 must be exactly 64 hex characters."
NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256="$(printf '%s' "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" | tr '[:upper:]' '[:lower:]')"
export NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256
PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"
[[ -f "$PRIVATE_DEVICE_RUNNER" ]] || die "Private intended-device reader is missing from the accepted source."
if ! DEVICE_UDID="$(/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT" <<'PY'
import hashlib
import hmac
import importlib.util
import os
import re
import sys
from pathlib import Path

runner_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("nembra_private_device_reader", runner_path)
if spec is None or spec.loader is None:
    raise RuntimeError("private intended-device reader could not be loaded")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
value = module.read_private_identifier(Path(sys.argv[2]), Path(sys.argv[3]))
expected_digest = os.environ.get("NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256", "")
if re.fullmatch(r"[0-9a-f]{64}", expected_digest) is None:
    raise RuntimeError("expected intended-device digest is unavailable or malformed")
actual_digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
if not hmac.compare_digest(actual_digest, expected_digest):
    raise RuntimeError("private intended-device identifier does not match Final GO authority")
sys.stdout.write(value)
PY
)"; then
    die "The intended-device verification file failed private custody validation."
fi
[[ -n "$DEVICE_UDID" ]] || die "The intended-device verification file produced no identifier."
unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 || true
say "Private intended-device admission validated against Final GO digest"

# The physical authentication candidate is the standalone Capture product with
# Tuya's app-specific security SDK and private app identity integrated through
# CocoaPods. Building the public .xcodeproj here would intentionally compile the
# fail-closed fallback and cannot authorize the ES80 experiment.
say "Validating official Tuya SDK and private app-identity provisioning"
run_accepted_source_bash "Scripts/bootstrap_capture_tuya_sdk.sh"
[[ -d "$ROOT/NembraCapture.xcworkspace" ]] || die "NembraCapture.xcworkspace was not generated. Do not use NembraCapture.xcodeproj for the authenticated field build."
verify_accepted_checkout_source "Private workspace bootstrap changed accepted-source inputs."
[[ -f "$ROOT/Podfile.lock" ]] || die "Private workspace bootstrap produced no Podfile.lock; reviewed Tuya dependency provenance is unavailable."
TUYA_DEPENDENCY_LOCK_SHA256="$(shasum -a 256 "$ROOT/Podfile.lock" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
[[ "$TUYA_DEPENDENCY_LOCK_SHA256" =~ ^[0-9a-f]{64}$ ]] || die "Could not compute a valid SHA-256 fingerprint for the resolved Tuya dependency lock."
say "Resolved Tuya dependency lock fingerprint captured for compiled provenance"

TUYA_PROVENANCE_HELPER_RELATIVE="Scripts/capture_tuya_private_input_provenance.py"
TUYA_BUILD_WINDOW_GUARD_RELATIVE="Scripts/capture_tuya_private_input_build_guard.py"
run_accepted_source_python() {
    local relative_path="$1"
    shift
    /usr/bin/python3 -I - "$ROOT" "$SOURCE_SHA" "$relative_path" "$@" <<'PY'
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
source_sha = sys.argv[2]
relative_path = sys.argv[3]
helper_argv = sys.argv[4:]
try:
    git_environment = {
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "LANG": "C",
        "LC_ALL": "C",
    }
    source = subprocess.check_output(
        ["/usr/bin/git", "show", f"{source_sha}:{relative_path}"],
        cwd=root,
        env=git_environment,
        stderr=subprocess.DEVNULL,
    )
except subprocess.CalledProcessError as error:
    raise SystemExit(f"accepted source helper is unavailable from exact Git authority: {relative_path}") from error
namespace = {"__name__": "__main__", "__file__": str(root / relative_path)}
sys.argv = [str(root / relative_path), *helper_argv]
exec(compile(source, f"<accepted-{source_sha}:{relative_path}>", "exec"), namespace)
PY
}
GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git cat-file -e "$SOURCE_SHA:$TUYA_BUILD_WINDOW_GUARD_RELATIVE" 2>/dev/null || die "Private Tuya build-window custody guard is missing from the exact accepted Git source."
TUYA_PRIVATE_SDK="$ROOT/LocalSecrets/TuyaSDK"
TUYA_PRIVATE_IDENTITY="$ROOT/LocalSecrets/TuyaRuntime"
TUYA_DEPENDENCY_PROVENANCE="$TUYA_PRIVATE_IDENTITY/ResolvedTuyaDependencyProvenance.txt"
verify_private_tuya_inputs() {
    run_accepted_source_python "$TUYA_PROVENANCE_HELPER_RELATIVE" verify \
        --lockfile "$ROOT/Podfile.lock" \
        --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
        --security-build "$TUYA_PRIVATE_SDK/Build" \
        --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
        --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
        --record "$TUYA_DEPENDENCY_PROVENANCE" >/dev/null || \
        die "Private Tuya SDK/app-identity inputs no longer match the bootstrap fingerprint record. Restart from a freshly reviewed field-build candidate."
}

# Never accept launch-time secrets. The field workspace gets AppKey/AppSecret
# from the ignored local NembraTuyaPrivateConfig pod generated by
# Scripts/provision_capture_tuya_identity.sh. Clearing these variables here
# prevents an old caller environment from becoming accidental authority.
unset NEMBRA_TUYA_APP_KEY NEMBRA_TUYA_APP_SECRET || true

say "Verifying the intended iPhone 12 / iOS 27 baseline"
DEVICE_ROWS="$(/usr/bin/xcrun xctrace list devices 2>/dev/null | /usr/bin/python3 -I -c '
import re,sys
section=False
for raw in sys.stdin:
    line=raw.strip()
    if line=="== Devices ==":
        section=True; continue
    if line.startswith("== "):
        section=False; continue
    if not section or "iPhone" not in line:
        continue
    m=re.search(r"\(([0-9A-Fa-f-]{20,})\)\s*$", line)
    if m:
        print(m.group(1)+"\t"+line[:m.start()].strip())
')"
[[ -n "$DEVICE_ROWS" ]] || die "No physical iPhone found. Connect the intended device by USB, unlock it, trust this Mac, and enable Developer Mode."

DEVICE_LABEL=""
DEVICE_OS_VERSION=""
MATCH_COUNT=0
INTENDED_NORMALIZED="$(printf '%s' "$DEVICE_UDID" | tr '[:upper:]' '[:lower:]')"
while IFS=$'\t' read -r ROW_UDID ROW_LABEL; do
    [[ -n "$ROW_UDID" ]] || continue
    ROW_NORMALIZED="$(printf '%s' "$ROW_UDID" | tr '[:upper:]' '[:lower:]')"
    if [[ "$ROW_NORMALIZED" == "$INTENDED_NORMALIZED" ]]; then
        MATCH_COUNT=$((MATCH_COUNT + 1))
        DEVICE_LABEL="$ROW_LABEL"
        if [[ "$ROW_LABEL" =~ \(([0-9]+(\.[0-9]+){1,2})\)$ ]]; then
            DEVICE_OS_VERSION="${BASH_REMATCH[1]}"
        fi
    fi
done <<< "$DEVICE_ROWS"
unset INTENDED_NORMALIZED ROW_NORMALIZED ROW_UDID
[[ "$MATCH_COUNT" == "1" && -n "$DEVICE_LABEL" ]] || die "The connected-device set does not contain exactly one match for the private intended iPhone. No arbitrary-device fallback is permitted."
[[ "$DEVICE_OS_VERSION" == 27.* ]] || die "The privately admitted intended iPhone is not currently reporting iOS 27 through Xcode device discovery. Do not use a different OS baseline."

# CoreDevice exposes a separate non-private selector and hardware product type.
# Correlate it to the private UDID through the device hostname, then use only the
# CoreDevice identifier for install/launch so the private UDID never enters
# devicectl argv. `--hide-headers` is an Xcode-supported textual-output option.
COREDEVICE_ROWS="$(/usr/bin/xcrun devicectl list devices --hide-headers 2>/dev/null || true)"
[[ -n "$COREDEVICE_ROWS" ]] || die "CoreDevice did not report the intended iPhone. Keep it connected/unlocked and allow Xcode device preparation to finish."
COREDEVICE_MATCH="$(printf '%s\0%s' "$DEVICE_UDID" "$COREDEVICE_ROWS" | /usr/bin/python3 -I -c '
import re,sys
payload=sys.stdin.buffer.read()
try:
    intended_raw, rows_raw = payload.split(b"\0", 1)
    intended=intended_raw.decode("utf-8").lower()
    rows=rows_raw.decode("utf-8")
except (ValueError, UnicodeDecodeError):
    raise SystemExit(2)
matches=[]
for raw in rows.splitlines():
    line=raw.strip()
    m=re.search(r"(\S+\.coredevice\.local)\s+([0-9A-Fa-f-]{36})\s+(.+)$", line)
    if not m:
        continue
    hostname, selector, tail=m.groups()
    if hostname.lower() != intended + ".coredevice.local":
        continue
    if re.search(r"\bunavailable\b", tail, re.IGNORECASE):
        continue
    models=re.findall(r"\b(iPhone[0-9]+,[0-9]+)\b", tail)
    if len(models) != 1:
        continue
    matches.append((selector, models[0]))
if len(matches) != 1:
    raise SystemExit(3)
sys.stdout.write(matches[0][0]+"\t"+matches[0][1])
')" || die "CoreDevice could not bind exactly one available non-private selector to the intended iPhone."
COREDEVICE_ID="${COREDEVICE_MATCH%%$'\t'*}"
DEVICE_MODEL="${COREDEVICE_MATCH#*$'\t'}"
[[ "$COREDEVICE_ID" =~ ^[0-9A-Fa-f-]{36}$ ]] || die "CoreDevice returned an invalid selector for the intended iPhone."
[[ "$DEVICE_MODEL" == "iPhone13,2" ]] || die "The privately admitted intended device is not the V14 iPhone 12 hardware baseline (expected product type iPhone13,2)."
unset COREDEVICE_MATCH COREDEVICE_ROWS DEVICE_ROWS DEVICE_LABEL DEVICE_MODEL
say "Intended baseline proven: iPhone 12 / iOS $DEVICE_OS_VERSION"

say "Finding Apple Development signing team"
TEAM_IDS="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/python3 -I -c '
import re,sys
seen=[]
for line in sys.stdin:
    if "Apple Development:" not in line:
        continue
    m=re.search(r"\(([A-Z0-9]{10})\)", line)
    if m and m.group(1) not in seen:
        seen.append(m.group(1))
print("\n".join(seen))
')"
TEAM_COUNT="$(printf '%s\n' "$TEAM_IDS" | sed '/^$/d' | wc -l | tr -d ' ')"
if [[ "$TEAM_COUNT" == "1" ]]; then
    TEAM_ID="$(printf '%s\n' "$TEAM_IDS" | sed '/^$/d')"
else
    if [[ "$TEAM_COUNT" -gt 1 ]]; then
        printf '%s\n' "$TEAM_IDS" | nl -w2 -s') '
        read -r -p "Choose Apple Development team number: " PICK
        TEAM_ID="$(printf '%s\n' "$TEAM_IDS" | sed -n "${PICK}p")"
    else
        read -r -p "Enter the 10-character Apple Team ID from Xcode Signing & Capabilities: " TEAM_ID
    fi
fi
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die "Could not determine a valid 10-character Team ID."

DERIVED="${TMPDIR:-/tmp}/NembraAuthenticatedCaptureDerived"
rm -rf "$DERIVED"
BUNDLE_ID="com.jonathangana131.nembra.capturelearn"
APP_ID_SUFFIX=".${BUNDLE_ID}"
PROCEDURE_ID="ES80-AUTHENTICATED-STATIONARY-v1"
BUILD_LABEL="capture-v14-${SOURCE_SHA:0:12}"
say "Field procedure: $PROCEDURE_ID"
verify_private_tuya_inputs

say "Building SDK-integrated Nembra Capture for the intended iPhone"
# Endpoint fingerprints alone cannot prove that a transient private-input change
# was not consumed by the compiler and restored before the post-build verify.
# Keep macOS vnode custody armed for every admitted private file/directory across
# the complete compiler/linker window, then retain the cryptographic verify below.
run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE" \
    --lockfile "$ROOT/Podfile.lock" \
    --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
    --security-build "$TUYA_PRIVATE_SDK/Build" \
    --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
    --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
    -- /usr/bin/xcodebuild \
    -workspace NembraCapture.xcworkspace \
    -scheme "Nembra Capture" \
    -configuration Debug \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    "NEMBRA_CAPTURE_BUILD_IDENTIFIER=$BUILD_LABEL" \
    "NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$SOURCE_SHA" \
    "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256" \
    "INFOPLIST_KEY_NembraCaptureProcedureIdentifier=$PROCEDURE_ID" \
    build || die "Private inputs changed while xcodebuild was running, vnode custody failed, or the signed build itself failed. No field artifact was admitted."

verify_private_tuya_inputs
verify_accepted_checkout_source "Accepted-source inputs changed while the field build was compiling. Discard this candidate and restart."
APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"
[[ -d "$APP" ]] || die "Build finished but the standalone Nembra Capture.app was not found at $APP"
APP_INFO_PLIST="$APP/Info.plist"
[[ -f "$APP_INFO_PLIST" ]] || die "Built Capture app is missing its Info.plist provenance subject. Discard this candidate."
BUILT_BUILD_IDENTIFIER="$(/usr/bin/plutil -extract NembraCaptureBuildIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_SOURCE_SHA="$(/usr/bin/plutil -extract NembraCaptureSourceCommitSHA raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_PROCEDURE_IDENTIFIER="$(/usr/bin/plutil -extract NembraCaptureProcedureIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
BUILT_BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"
[[ "$BUILT_BUILD_IDENTIFIER" == "$BUILD_LABEL" ]] || die "Built Capture app identifier does not match the exact requested field-build label. Discard this candidate."
[[ "$BUILT_SOURCE_SHA" == "$SOURCE_SHA" ]] || die "Built Capture app source SHA does not match the exact requested source. Discard this candidate."
[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."
[[ "$BUILT_PROCEDURE_IDENTIFIER" == "$PROCEDURE_ID" ]] || die "Built Capture app procedure identity does not match the canonical stationary procedure. Discard this candidate."
[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]] || die "Built Capture app bundle identifier does not match the intended standalone field product. Discard this candidate."
say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, canonical stationary procedure, and field product"

# Entitlement/profile readback proves identity values, but it does not prove the app bundle's
# recursive signature/seal is valid. Fail closed on the exact signed bytes before those values
# are allowed to participate in field authority or before any device installation is attempted.
if ! /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
    die "Final signed Capture app failed recursive strict code-signature verification. Discard this candidate."
fi
say "Final signed Capture app passed recursive strict code-signature verification"

# Apple-backed Smart Life account entry is now part of field preflight. A source entitlement file
# is not enough: prove the final signed executable and the exact embedded provisioning profile both
# authorize Sign in with Apple before this build can be installed as the field candidate. Run the
# Apple verifiers with a closed startup environment and parse an XML plist from either display stream.
SIGNED_ENTITLEMENTS_OUTPUT="$(/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign -d --entitlements :- --xml "$APP" 2>&1)" || \
    die "Could not read effective entitlements from the final signed Capture app. Discard this candidate."
BUILT_SIGNING_IDENTITY="$(printf '%s' "$SIGNED_ENTITLEMENTS_OUTPUT" | /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '
import plistlib, sys
payload = sys.stdin.buffer.read()
start = payload.find(b"<?xml")
end = payload.rfind(b"</plist>")
if start < 0 or end < start:
    raise SystemExit(2)
try:
    entitlements = plistlib.loads(payload[start:end + len(b"</plist>")])
    apple = entitlements.get("com.apple.developer.applesignin")
    application = entitlements.get("application-identifier")
    team = entitlements.get("com.apple.developer.team-identifier")
except Exception:
    raise SystemExit(2)
if apple == ["Default"] and isinstance(application, str) and isinstance(team, str):
    sys.stdout.write(application + "\t" + team)
' || true)"
[[ "$BUILT_SIGNING_IDENTITY" == *$'\t'* ]] || \
    die "Final signed Capture app is missing required Sign in with Apple or exact application/team identity entitlements. Discard this candidate."
BUILT_APPLICATION_IDENTIFIER="${BUILT_SIGNING_IDENTITY%%$'\t'*}"
BUILT_TEAM_IDENTIFIER="${BUILT_SIGNING_IDENTITY#*$'\t'}"
[[ "$BUILT_APPLICATION_IDENTIFIER" == *"$APP_ID_SUFFIX" ]] || \
    die "Final signed Capture app application-identifier does not end in the exact Capture bundle identifier. Discard this candidate."
[[ "$BUILT_APPLICATION_IDENTIFIER" != *"*"* ]] || \
    die "Final signed Capture app application-identifier is wildcard/ambiguous. Discard this candidate."
BUILT_APP_ID_PREFIX="${BUILT_APPLICATION_IDENTIFIER%$APP_ID_SUFFIX}"
[[ -n "$BUILT_APP_ID_PREFIX" && "$BUILT_APP_ID_PREFIX" != "$BUILT_APPLICATION_IDENTIFIER" ]] || \
    die "Final signed Capture app application-identifier is missing a concrete App ID prefix. Discard this candidate."
[[ "$BUILT_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \
    die "Final signed Capture app team identifier does not match the selected Apple Development team. Discard this candidate."

BUILT_PROFILE="$APP/embedded.mobileprovision"
[[ -f "$BUILT_PROFILE" ]] || die "Final signed Capture app is missing embedded.mobileprovision. Discard this candidate."
PROFILE_PLIST_XML="$(/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security cms -D -i "$BUILT_PROFILE" 2>/dev/null)" || \
    die "Could not decode the exact provisioning profile embedded in the final signed Capture app. Discard this candidate."
PROFILE_SIGNING_IDENTITY="$(printf '%s' "$PROFILE_PLIST_XML" | /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '
import plistlib, sys
try:
    root = plistlib.loads(sys.stdin.buffer.read())
    entitlements = root.get("Entitlements", {})
    apple = entitlements.get("com.apple.developer.applesignin")
    application = entitlements.get("application-identifier")
    entitlement_team = entitlements.get("com.apple.developer.team-identifier")
    team_identifiers = root.get("TeamIdentifier")
except Exception:
    raise SystemExit(2)
if (apple == ["Default"] and isinstance(application, str) and isinstance(entitlement_team, str)
        and isinstance(team_identifiers, list) and len(team_identifiers) == 1
        and isinstance(team_identifiers[0], str)):
    sys.stdout.write(application + "\t" + entitlement_team + "\t" + team_identifiers[0])
' || true)"
[[ "$PROFILE_SIGNING_IDENTITY" == *$'\t'*$'\t'* ]] || \
    die "Embedded provisioning profile is missing required Sign in with Apple or exact application/team identity custody. Discard this candidate."
PROFILE_APPLICATION_IDENTIFIER="${PROFILE_SIGNING_IDENTITY%%$'\t'*}"
PROFILE_TEAM_FIELDS="${PROFILE_SIGNING_IDENTITY#*$'\t'}"
PROFILE_TEAM_IDENTIFIER="${PROFILE_TEAM_FIELDS%%$'\t'*}"
PROFILE_ROOT_TEAM_IDENTIFIER="${PROFILE_TEAM_FIELDS#*$'\t'}"
[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$BUILT_APPLICATION_IDENTIFIER" ]] || \
    die "Embedded provisioning profile application identifier does not exactly match the final signed Capture app. Discard this candidate."
[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \
    die "Embedded provisioning profile entitlement team identity does not match the selected Apple Development team. Discard this candidate."
[[ "$PROFILE_ROOT_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \
    die "Embedded provisioning profile root TeamIdentifier does not match the selected Apple Development team. Discard this candidate."
say "Final signed app and embedded provisioning profile authorize Sign in with Apple for one exact App ID and the selected team"
unset SIGNED_ENTITLEMENTS_OUTPUT BUILT_SIGNING_IDENTITY BUILT_APPLICATION_IDENTIFIER BUILT_TEAM_IDENTIFIER BUILT_APP_ID_PREFIX PROFILE_PLIST_XML PROFILE_SIGNING_IDENTITY PROFILE_APPLICATION_IDENTIFIER PROFILE_TEAM_FIELDS PROFILE_TEAM_IDENTIFIER PROFILE_ROOT_TEAM_IDENTIFIER BUILT_PROFILE APP_ID_SUFFIX
unset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_PROCEDURE_IDENTIFIER BUILT_BUNDLE_ID APP_INFO_PLIST

say "Installing SDK-integrated Capture on the intended iPhone"
open -a Xcode "$ROOT/NembraCapture.xcworkspace" >/dev/null 2>&1 || true
INSTALL_LOG="$(mktemp "${TMPDIR:-/tmp}/nembra-authenticated-capture-install.XXXXXX")"
trap 'rm -f -- "$INSTALL_LOG"' EXIT
chmod 600 "$INSTALL_LOG"
INSTALLED=0
for ATTEMPT in $(seq 1 60); do
    if xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP" >"$INSTALL_LOG" 2>&1; then
        INSTALLED=1
        break
    fi
    if [[ "$ATTEMPT" == "1" ]]; then
        printf '%s\n' "Xcode still appears to be preparing the intended iPhone. Keep it plugged in and unlocked; installation will retry automatically."
    fi
    sleep 3
done

if [[ "$INSTALLED" != "1" ]]; then
    if [[ -s "$INSTALL_LOG" ]]; then
        INSTALL_DIAGNOSTIC="$(
            printf '%s\0%s' "$DEVICE_UDID" "$COREDEVICE_ID" | /usr/bin/python3 -I -c '
import re
import sys
from pathlib import Path
payload = sys.stdin.buffer.read()
try:
    private_udid_raw, selector_raw = payload.split(b"\0", 1)
    private_udid = private_udid_raw.decode("utf-8")
    selector = selector_raw.decode("utf-8")
except (ValueError, UnicodeDecodeError):
    raise SystemExit(2)
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
secrets = (
    (private_udid, "<redacted-device>"),
    (selector, "<redacted-device-selector>"),
)
for secret, replacement in secrets:
    for variant in sorted({secret, secret.replace("-", "")}, key=len, reverse=True):
        if variant:
            text = re.sub(re.escape(variant), replacement, text, flags=re.IGNORECASE)
sys.stdout.write(text)
' "$INSTALL_LOG"
        )"
        printf '%s\n' "$INSTALL_DIAGNOSTIC" >&2
        unset INSTALL_DIAGNOSTIC
    fi
    die "The app built successfully, but the intended iPhone never became ready for installation. Keep it unlocked and connected, wait for Xcode to finish Preparing/Connecting, then run this installer again."
fi

say "Launching privately provisioned Capture on the intended iPhone"
if ! xcrun devicectl device process launch \
    --device "$COREDEVICE_ID" \
    --activate \
    "$BUNDLE_ID" >/dev/null 2>&1; then
    die "Capture installed, but devicectl could not launch it on the intended iPhone. Do not promote the physical test; relaunch through this installer after the device is ready."
fi
unset DEVICE_UDID COREDEVICE_ID DEVICE_OS_VERSION
rm -f -- "$INSTALL_LOG"
trap - EXIT

say "SDK-INTEGRATED CAPTURE LAUNCHED"
printf '%s\n' \
    "This launch used no Tuya secret in host argv, environment, Git, or the diagnostic export." \
    "The private intended-device UDID was used only for local correlation and was not placed in devicectl argv." \
    "The exact private Tuya security SDK, resolved lockfile, and generated private app identity matched the bootstrap fingerprint before and after the signed build." \
    "The exact built device app was read back before installation and matched the requested source SHA, field-build identifier, canonical stationary procedure, and standalone bundle identifier." \
    "Field procedure: $PROCEDURE_ID. The same identifier is compiled into the immutable accepted export and shown in Capture." \
    "Do NOT repeat the old 17-step ride capture." \
    "Keep the scooter stationary for this first preflight." \
    "If Capture says SDK compiled/configured, account logged in, exact scooter membership, or field-build provenance is not proven, STOP and do not start Bluetooth correlation." \
    "Only after every app authority gate is green: complete the package-owned OFF1 -> ON1 -> OFF2 -> ON2 correlation in order, wait for each fresh-manager scanner to report Live and satisfy the receipt-bounded window before sealing it, then explicitly confirm the single repeatable correlated target for this attempt before starting the secure read-only test." \
    "A correlated target is current-session evidence only; it is not permanent scooter identity, and name/RSSI/FD50/Tuya-company/historical UUID hints never substitute for the four-window result." \
    "PASS requires exact SDK scooter membership, same-account source authority, Tuya local BLE online, a genuine same-generation dpsUpdate, canonical continuity of at least 45 seconds, a sealed accepted prefix, and no command/pair/reset/unbind action." \
    "If any gate fails, correlation is ambiguous, the app reports source/continuity/lifecycle failure, or the package cannot seal the accepted prefix, share the sanitized diagnostic JSON and stop. No outdoor ride is authorized by this installer."
