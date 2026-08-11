#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import hashlib
import subprocess
import textwrap

ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
BOOTSTRAP = ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh"
TEST = ROOT / "scripts/ci/tests/test_capture_field_installer_git_authority_red_team.py"
TEMP_SCRIPT = ROOT / "scripts/ci/tmp_materialize_field_installer_git_authority_sol.py"
TEMP_WORKFLOW = ROOT / ".github/workflows/tmp-v14-field-installer-git-authority-materialize-sol.yml"
EXPECTED_INSTALLER_BLOB = "114d01363d96352ca0d7c5c8a3faf90bd127b1ae"
EXPECTED_BOOTSTRAP_BLOB = "cd441df5b154e508668b76fc11758412579f1631"


def git_blob(path: Path) -> str:
    data = path.read_bytes()
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    return source.replace(old, new, 1)


if git_blob(INSTALLER) != EXPECTED_INSTALLER_BLOB:
    raise SystemExit("installer production blob moved; refusing stale materialization")
if git_blob(BOOTSTRAP) != EXPECTED_BOOTSTRAP_BLOB:
    raise SystemExit("bootstrap production blob moved; refusing stale materialization")

installer = INSTALLER.read_text(encoding="utf-8")
old_authority = '''EXPECTED_SOURCE_SHA="${1:-${NEMBRA_CAPTURE_EXPECTED_SOURCE_SHA:-}}"
[[ "$EXPECTED_SOURCE_SHA" =~ ^[0-9A-Fa-f]{40}$ ]] || die "Pass the exact software-accepted Capture source SHA as the first argument (40 hex characters)."
EXPECTED_SOURCE_SHA="$(printf '%s' "$EXPECTED_SOURCE_SHA" | tr '[:upper:]' '[:lower:]')"
SOURCE_SHA="$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')"
[[ "$SOURCE_SHA" == "$EXPECTED_SOURCE_SHA" ]] || die "Current checkout $SOURCE_SHA does not match accepted Capture source $EXPECTED_SOURCE_SHA. Checkout the exact accepted SHA before building."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Working tree has local changes. Commit/stash them first."
say "Exact requested Capture source matched: $SOURCE_SHA"
'''
new_authority = r'''EXPECTED_SOURCE_SHA="${1:-${NEMBRA_CAPTURE_EXPECTED_SOURCE_SHA:-}}"
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

allowed_roots = {"LocalSecrets", "Pods", "NembraCapture.xcworkspace"}
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
'''
installer = replace_once(installer, old_authority, new_authority, "initial source authority")

old_bootstrap_call = '''say "Validating official Tuya SDK and private app-identity provisioning"
"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"
[[ -d "$ROOT/NembraCapture.xcworkspace" ]] || die "NembraCapture.xcworkspace was not generated. Do not use NembraCapture.xcodeproj for the authenticated field build."
[[ "$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')" == "$SOURCE_SHA" ]] || die "Repository HEAD changed during private workspace bootstrap. Restart from the exact accepted source."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Private workspace bootstrap changed tracked or unignored accepted-source inputs. Review and re-accept before building."
'''
new_bootstrap_call = '''say "Validating official Tuya SDK and private app-identity provisioning"
run_accepted_source_bash "Scripts/bootstrap_capture_tuya_sdk.sh"
[[ -d "$ROOT/NembraCapture.xcworkspace" ]] || die "NembraCapture.xcworkspace was not generated. Do not use NembraCapture.xcodeproj for the authenticated field build."
verify_accepted_checkout_source "Private workspace bootstrap changed accepted-source inputs."
'''
installer = replace_once(installer, old_bootstrap_call, new_bootstrap_call, "bootstrap execution boundary")

old_postbuild = '''verify_private_tuya_inputs
[[ "$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')" == "$SOURCE_SHA" ]] || die "Repository HEAD changed while the accepted field build was compiling. Discard this candidate."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Accepted-source inputs changed while the field build was compiling. Discard this candidate and restart."
APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"
'''
new_postbuild = '''verify_private_tuya_inputs
verify_accepted_checkout_source "Accepted-source inputs changed while the field build was compiling. Discard this candidate and restart."
APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"
'''
installer = replace_once(installer, old_postbuild, new_postbuild, "post-build source authority")
INSTALLER.write_text(installer, encoding="utf-8")

bootstrap = BOOTSTRAP.read_text(encoding="utf-8")
bootstrap = replace_once(
    bootstrap,
    'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"',
    'SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"',
    "bootstrap accepted-stdin path identity",
)
BOOTSTRAP.write_text(bootstrap, encoding="utf-8")

for command in (
    ["bash", "-n", str(INSTALLER)],
    ["bash", "-n", str(BOOTSTRAP)],
    ["/usr/bin/python3", "-m", "py_compile", str(TEST)],
    ["/usr/bin/python3", str(TEST)],
    ["git", "diff", "--check"],
):
    subprocess.run(command, cwd=ROOT, check=True)

for temporary in (TEMP_SCRIPT, TEMP_WORKFLOW):
    if temporary.exists():
        temporary.unlink()
