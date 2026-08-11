#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import hashlib
import subprocess

ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
TEST = ROOT / "scripts/ci/tests/test_capture_field_installer_git_authority_red_team.py"
TEMP_SCRIPT = ROOT / "scripts/ci/tmp_materialize_field_shell_tool_authority_sol.py"
TEMP_WORKFLOW = ROOT / ".github/workflows/tmp-v14-field-shell-tool-authority-sol.yml"
EXPECTED_INSTALLER_BLOB = "fa68975764d4e95e153264c603a9d72cbd8990f9"


def git_blob(path: Path) -> str:
    data = path.read_bytes()
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    return source.replace(old, new, 1)


if git_blob(INSTALLER) != EXPECTED_INSTALLER_BLOB:
    raise SystemExit("installer moved; refusing stale shell/tool materialization")

source = INSTALLER.read_text(encoding="utf-8")
source = replace_once(
    source,
    "#!/bin/bash\nset -euo pipefail\n\n",
    "#!/bin/bash -p\nset -euo pipefail\nPATH=\"/usr/bin:/bin:/usr/sbin:/sbin\"\nexport PATH\nunset BASH_ENV ENV CDPATH || true\nhash -r\n\n",
    "privileged entry and PATH fence",
)
source = replace_once(source, 'command -v xcodebuild >/dev/null || die "Xcode command-line tools are not available."', '[[ -x /usr/bin/xcodebuild ]] || die "Xcode command-line tools are not available."', "xcodebuild admission")
source = replace_once(source, 'command -v xcrun >/dev/null || die "xcrun is not available."', '[[ -x /usr/bin/xcrun ]] || die "xcrun is not available."', "xcrun admission")
source = replace_once(source, 'command -v security >/dev/null || die "macOS security tool is not available."', '[[ -x /usr/bin/security ]] || die "macOS security tool is not available."', "security admission")
source = replace_once(source, 'command -v pod >/dev/null || die "CocoaPods is required for the official Tuya SDK field build."\n', '', "unused physical pod admission")
source = source.replace("$(xcrun xctrace list devices", "$(/usr/bin/xcrun xctrace list devices")
source = source.replace("$(xcrun devicectl list devices", "$(/usr/bin/xcrun devicectl list devices")
source = source.replace("$(security find-identity", "$(/usr/bin/security find-identity")
source = replace_once(source, "    -- xcodebuild \\\n", "    -- /usr/bin/xcodebuild \\\n", "guarded xcodebuild executable")
INSTALLER.write_text(source, encoding="utf-8")

for command in (
    ["bash", "-n", str(INSTALLER)],
    ["/usr/bin/python3", str(TEST)],
    ["git", "diff", "--check"],
):
    subprocess.run(command, cwd=ROOT, check=True)

for temporary in (TEMP_SCRIPT, TEMP_WORKFLOW):
    if temporary.exists():
        temporary.unlink()
