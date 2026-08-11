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
    "xcode-select availability",
)

custody_marker = '[[ -x /usr/bin/security ]] || die "System security is required for embedded provisioning-profile verification."\n\n'
custody_block = '''[[ -x /usr/bin/security ]] || die "System security is required for embedded provisioning-profile verification."

validate_root_custodied_path() {
    local candidate="$1"
    local expected_kind="$2"
    /usr/bin/env -i \\
        PATH=/usr/bin:/bin \\
        HOME=/tmp \\
        LANG=C \\
        LC_ALL=C \\
        NEMBRA_CUSTODY_PATH="$candidate" \\
        NEMBRA_CUSTODY_KIND="$expected_kind" \\
        /usr/bin/python3 -I - <<'PY_CUSTODY'
import os
from pathlib import Path
import stat

raw = os.environ.get("NEMBRA_CUSTODY_PATH", "")
kind = os.environ.get("NEMBRA_CUSTODY_KIND", "")
path = Path(raw)
if not raw or "\\x00" in raw or not path.is_absolute():
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
SELECTED_XCODE_FIRST_LINE="${SELECTED_XCODE_VERSION%%$'\\n'*}"
[[ "$SELECTED_XCODE_FIRST_LINE" =~ ^Xcode[[:space:]]27([.]|$) ]] || die "Selected developer tree must identify as Xcode 27 before physical device discovery or build admission."
SELECTED_XCODEBUILD="$(DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" /usr/bin/xcrun --find xcodebuild)" || die "Could not resolve xcodebuild from the selected Xcode 27 developer tree."
readonly SELECTED_XCODEBUILD
[[ "$SELECTED_XCODEBUILD" == "$SELECTED_DEVELOPER_DIR"/* ]] || die "Selected xcodebuild escaped the admitted Xcode developer tree."
validate_root_custodied_path "$(dirname "$SELECTED_XCODEBUILD")" directory || die "Selected xcodebuild parent escaped trusted root custody."
[[ -f "$SELECTED_XCODEBUILD" && -x "$SELECTED_XCODEBUILD" && ! -L "$SELECTED_XCODEBUILD" ]] || die "Selected xcodebuild is not one real executable under the admitted Xcode tree."
say "Selected Xcode 27 developer tree admitted under root custody"
unset SELECTED_XCODE_VERSION SELECTED_XCODE_FIRST_LINE || true

'''
installer = replace_once(installer, custody_marker, custody_block, "selected Xcode custody insertion")

# Every physical xcrun call is explicitly pinned to the one selected developer
# tree. The initial executable-presence check above is not rewritten.
plain_xcrun = re.compile(r'(?m)(?<!/usr/bin/)\bxcrun (?=(?:xctrace|devicectl)\b)')
installer, plain_count = plain_xcrun.subn(
    'DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" /usr/bin/xcrun ', installer
)
absolute_xcrun = re.compile(r'(?m)(?<!-x )/usr/bin/xcrun (?=(?:xctrace|devicectl)\b)')
installer, absolute_count = absolute_xcrun.subn(
    'DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" /usr/bin/xcrun ', installer
)
if plain_count + absolute_count < 3:
    raise SystemExit(
        f"expected at least three physical xcrun call sites, found {plain_count + absolute_count}"
    )

build_seam = '    -- /usr/bin/xcodebuild \\\n'
installer = replace_once(
    installer,
    build_seam,
    '    -- "$SELECTED_XCODEBUILD" \\\n',
    "guarded xcodebuild executable",
)
installer_path.write_text(installer, encoding="utf-8")

# Strengthen the carried expected-red contract: not only must the selected tree
# be admitted before discovery, the exact tree must drive xcrun and the exact
# xcodebuild executable resolved from that tree must cross the guarded build
# boundary. This preserves #2949's closed child environment without ambient
# DEVELOPER_DIR authority.
test_path = Path("scripts/ci/tests/test_capture_field_selected_xcode_custody.py")
test_source = test_path.read_text(encoding="utf-8")
anchor = '''    def test_caller_fence_alone_is_not_misrepresented_as_selected_toolchain_custody(self) -> None:
        self._selected_developer_dir()
        self.assertIn(
            "xcode-select",
            self.source,
            "selected developer-directory authority must remain explicit after caller overrides are cleared",
        )
'''
addition = anchor + '''
    def test_same_selected_tree_drives_device_tools_and_guarded_xcodebuild(self) -> None:
        name, _ = self._selected_developer_dir()
        self.assertRegex(
            self.source,
            re.compile(rf'DEVELOPER_DIR="?\\${name}"?\\s+/usr/bin/xcrun\\s+(?:xctrace|devicectl)'),
            "physical device tooling must be explicitly pinned to the admitted selected developer tree",
        )
        self.assertIn(
            'SELECTED_XCODEBUILD="$(DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" /usr/bin/xcrun --find xcodebuild)"',
            self.source,
        )
        self.assertIn(
            '-- "$SELECTED_XCODEBUILD"',
            self.source,
            "the vnode-guarded compiler must execute the exact xcodebuild resolved from the admitted selected tree",
        )
        self.assertNotIn(
            '-- /usr/bin/xcodebuild',
            self.source,
            "the guarded physical build must not fall back to the mutable system Xcode dispatcher after custody",
        )
'''
test_source = replace_once(test_source, anchor, addition, "selected Xcode strengthened regression")
test_path.write_text(test_source, encoding="utf-8")
