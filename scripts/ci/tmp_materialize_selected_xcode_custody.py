#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label} seam count={count}")
    return source.replace(old, new, 1)


installer_path = Path("scripts/field/install_one_time_capture.command")
installer = installer_path.read_text(encoding="utf-8")

xcrun_check = '[[ -x /usr/bin/xcrun ]] || die "xcrun is not available."\n'
installer = replace_once(
    installer,
    xcrun_check,
    xcrun_check + '[[ -x /usr/bin/xcode-select ]] || die "xcode-select is not available."\n',
    "xcrun availability",
)

custody_marker = '[[ -x /usr/bin/security ]] || die "System security is required for embedded provisioning-profile verification."\n\n'
custody_block = r'''[[ -x /usr/bin/security ]] || die "System security is required for embedded provisioning-profile verification."

validate_root_custodied_path() {
    local candidate="$1"
    local expected_kind="$2"
    /usr/bin/env -i \
        PATH=/usr/bin:/bin \
        HOME=/tmp \
        LANG=C \
        LC_ALL=C \
        NEMBRA_CUSTODY_PATH="$candidate" \
        NEMBRA_CUSTODY_KIND="$expected_kind" \
        /usr/bin/python3 -I - <<'PY_CUSTODY'
import os
from pathlib import Path
import stat

raw = os.environ.get("NEMBRA_CUSTODY_PATH", "")
kind = os.environ.get("NEMBRA_CUSTODY_KIND", "")
path = Path(raw)
if not raw or "\x00" in raw or not path.is_absolute():
    raise SystemExit("selected Xcode custody requires one absolute path")
try:
    resolved = path.resolve(strict=True)
except OSError as error:
    raise SystemExit("selected Xcode custody path is unavailable") from error
if resolved != path:
    raise SystemExit("selected Xcode custody refuses symlink/alias resolution")
current = Path(path.anchor)
for component in path.parts[1:]:
    current = current / component
    try:
        metadata = os.lstat(current)
    except OSError as error:
        raise SystemExit("selected Xcode custody ancestry is unavailable") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise SystemExit("selected Xcode custody requires real directory ancestry")
    if metadata.st_uid != 0 or metadata.st_mode & 0o022:
        raise SystemExit("selected Xcode custody requires root-owned non-group/world-writable ancestry")
if kind != "directory" or not path.is_dir():
    raise SystemExit("selected Xcode custody expected one directory")
PY_CUSTODY
}

SELECTED_DEVELOPER_DIR="$(/usr/bin/xcode-select -p)" || die "Could not resolve the system-selected Xcode developer directory."
readonly SELECTED_DEVELOPER_DIR
[[ "$SELECTED_DEVELOPER_DIR" == /* ]] || die "System-selected Xcode developer directory is not absolute."
validate_root_custodied_path "$SELECTED_DEVELOPER_DIR" directory || die "System-selected Xcode developer tree is not under trusted root custody."
SELECTED_XCODE_VERSION="$(DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" /usr/bin/xcodebuild -version 2>/dev/null)" || die "Could not interrogate the selected Xcode toolchain."
SELECTED_XCODE_FIRST_LINE="${SELECTED_XCODE_VERSION%%$'\n'*}"
[[ "$SELECTED_XCODE_FIRST_LINE" =~ ^Xcode[[:space:]]27([.]|$) ]] || die "Selected developer tree must identify as Xcode 27 before physical device discovery or build admission."
say "Selected Xcode 27 developer tree admitted under root custody"
unset SELECTED_XCODE_VERSION SELECTED_XCODE_FIRST_LINE || true

'''
installer = replace_once(installer, custody_marker, custody_block, "custody insertion")

xcrun_pattern = re.compile(r'(?<!-x )/usr/bin/xcrun (?=(?:xctrace|devicectl)\b)')
installer, xcrun_count = xcrun_pattern.subn(
    'DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" /usr/bin/xcrun ', installer
)
if xcrun_count < 3:
    raise SystemExit(f"expected at least three physical xcrun call sites, found {xcrun_count}")

guard_argument = '    --accepted-source-sha "$SOURCE_SHA" \\\n'
pinned_guard_argument = guard_argument + '    --developer-dir "$SELECTED_DEVELOPER_DIR" \\\n'
installer = replace_once(
    installer,
    guard_argument,
    pinned_guard_argument,
    "guard selected-developer argument",
)
installer_path.write_text(installer, encoding="utf-8")

guard_path = Path("Scripts/capture_tuya_private_input_build_guard.py")
guard = guard_path.read_text(encoding="utf-8")

dataclass_seam = '    accepted_source_root: Path | None = None\n    accepted_source_sha: str | None = None\n'
guard = replace_once(
    guard,
    dataclass_seam,
    dataclass_seam + '    selected_developer_dir: Path | None = None\n',
    "PrivateInputs selected developer",
)

helper_marker = 'def _closed_xcode_environment() -> dict[str, str]:\n'
helper_prefix = r'''def _require_root_custodied_directory(path: Path, *, label: str) -> Path:
    candidate = path.expanduser()
    if not candidate.is_absolute() or "\x00" in str(candidate):
        raise BuildGuardError(f"{label} must be one absolute path")
    try:
        resolved = candidate.resolve(strict=True)
    except OSError as error:
        raise BuildGuardError(f"{label} is unavailable") from error
    if resolved != candidate:
        raise BuildGuardError(f"{label} must not traverse symlink/alias ancestry")
    current = Path(candidate.anchor)
    for component in candidate.parts[1:]:
        current = current / component
        try:
            metadata = os.lstat(current)
        except OSError as error:
            raise BuildGuardError(f"{label} ancestry is unavailable") from error
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise BuildGuardError(f"{label} must have real directory ancestry")
        if metadata.st_uid != 0 or metadata.st_mode & 0o022:
            raise BuildGuardError(f"{label} ancestry must be root-owned and not group/world writable")
    return candidate


def _closed_xcode_environment(selected_developer_dir: Path | None) -> dict[str, str]:
'''
guard = replace_once(guard, helper_marker, helper_prefix, "closed environment helper")

old_return = '''    return {\n        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",\n        "HOME": home,\n        "USER": account.pw_name,\n        "LOGNAME": account.pw_name,\n        "LANG": "en_US.UTF-8",\n    }\n'''
new_return = '''    environment = {\n        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",\n        "HOME": home,\n        "USER": account.pw_name,\n        "LOGNAME": account.pw_name,\n        "LANG": "en_US.UTF-8",\n    }\n    if selected_developer_dir is not None:\n        developer_dir = str(selected_developer_dir)\n        if not os.path.isabs(developer_dir) or "\\x00" in developer_dir:\n            raise BuildGuardError("selected Xcode developer directory is invalid at compiler admission")\n        environment["DEVELOPER_DIR"] = developer_dir\n    return environment\n'''
guard = replace_once(guard, old_return, new_return, "closed environment return")

spawn = '        process = popen_factory(list(command), env=_closed_xcode_environment())\n'
guard = replace_once(
    guard,
    spawn,
    '        process = popen_factory(list(command), env=_closed_xcode_environment(inputs.selected_developer_dir))\n',
    "compiler spawn",
)

parser_seam = '    parser.add_argument("--accepted-source-sha")\n'
guard = replace_once(
    guard,
    parser_seam,
    parser_seam + '    parser.add_argument("--developer-dir", type=Path)\n',
    "developer-dir parser",
)

parse_seam = '''        accepted_source_sha = args.accepted_source_sha.lower()\n\n    return (\n'''
parse_replacement = '''        accepted_source_sha = args.accepted_source_sha.lower()\n\n    selected_developer_dir: Path | None = None\n    if args.developer_dir is not None:\n        selected_developer_dir = _require_root_custodied_directory(\n            args.developer_dir, label="selected Xcode developer directory"\n        )\n\n    return (\n'''
guard = replace_once(guard, parse_seam, parse_replacement, "developer-dir parse")

constructor_seam = '            accepted_source_sha=accepted_source_sha,\n'
guard = replace_once(
    guard,
    constructor_seam,
    constructor_seam + '            selected_developer_dir=selected_developer_dir,\n',
    "PrivateInputs constructor",
)

tracked_seam = '''        tracked_manifest = _accepted_tracked_source_manifest(\n            inputs.accepted_source_root, inputs.accepted_source_sha\n        )\n\n    if require_accepted_generated_subject:\n'''
tracked_replacement = '''        tracked_manifest = _accepted_tracked_source_manifest(\n            inputs.accepted_source_root, inputs.accepted_source_sha\n        )\n        if inputs.selected_developer_dir is None:\n            raise BuildGuardError("selected Xcode developer directory is required for physical xcodebuild custody")\n\n    if require_accepted_generated_subject:\n'''
guard = replace_once(guard, tracked_seam, tracked_replacement, "physical selected developer requirement")
guard_path.write_text(guard, encoding="utf-8")

env_test_path = Path("scripts/ci/tests/test_capture_field_xcode_environment_authority.py")
env_test = env_test_path.read_text(encoding="utf-8")
env_test = replace_once(
    env_test,
    '            "_closed_xcode_environment()",\n',
    '            "_closed_xcode_environment(inputs.selected_developer_dir)",\n',
    "xcode env call assertion",
)
env_test = replace_once(
    env_test,
    '            "DEVELOPER_DIR",\n',
    "",
    "DEVELOPER_DIR forbidden literal",
)
required_loop = '''        for required in (\n            "PATH",\n            "/usr/bin:/bin:/usr/sbin:/sbin",\n            "HOME",\n            "USER",\n            "LOGNAME",\n        ):\n            self.assertIn(required, literals, f"closed compiler child environment omitted {required}")\n\n'''
env_test = replace_once(
    env_test,
    required_loop,
    required_loop + '        self.assertIn("DEVELOPER_DIR", literals)\n        self.assertIn("selected_developer_dir", rendered)\n\n',
    "xcode env required literals",
)
env_test_path.write_text(env_test, encoding="utf-8")
