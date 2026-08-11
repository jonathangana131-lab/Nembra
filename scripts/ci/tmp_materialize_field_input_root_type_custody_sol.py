#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import hashlib
import subprocess

ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
TEST = ROOT / "scripts/ci/tests/test_capture_field_installer_git_authority_red_team.py"
TEMP_SCRIPT = ROOT / "scripts/ci/tmp_materialize_field_input_root_type_custody_sol.py"
TEMP_WORKFLOW = ROOT / ".github/workflows/tmp-v14-field-input-root-type-custody-sol.yml"
EXPECTED_INSTALLER_BLOB = "d735a673a94ebc99f0a89ce4d370bc0d458c3739"
EXPECTED_TEST_BLOB = "1a64a2e5c7348608cc22b2ac750ae9e19890932e"


def git_blob(path: Path) -> str:
    data = path.read_bytes()
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if source.count(old) != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {source.count(old)}")
    return source.replace(old, new, 1)


if git_blob(INSTALLER) != EXPECTED_INSTALLER_BLOB:
    raise SystemExit("installer moved; refusing stale root-type materialization")
if git_blob(TEST) != EXPECTED_TEST_BLOB:
    raise SystemExit("red-team test moved; refusing stale root-type materialization")

installer = INSTALLER.read_text(encoding="utf-8")
old = '''allowed_roots = {"LocalSecrets", "Pods", "NembraCapture.xcworkspace"}
for current_raw, directories, files in os.walk(root, topdown=True, followlinks=False):
'''
new = '''field_input_directories = ("LocalSecrets", "Pods", "NembraCapture.xcworkspace")
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
'''
installer = replace_once(installer, old, new, "field-input allowlist root admission")
INSTALLER.write_text(installer, encoding="utf-8")

test = TEST.read_text(encoding="utf-8")
old_marker = '''            'untracked accepted-source path outside field-input allowlist',
        ):
'''
new_marker = '''            'untracked accepted-source path outside field-input allowlist',
            'field-input allowlist root must be one real directory',
            'field-input allowlist lockfile must be one real regular file',
        ):
'''
test = replace_once(test, old_marker, new_marker, "root-type static contract")
TEST.write_text(test, encoding="utf-8")

for command in (
    ["bash", "-n", str(INSTALLER)],
    ["/usr/bin/python3", str(TEST)],
    ["git", "diff", "--check"],
):
    subprocess.run(command, cwd=ROOT, check=True)

for temporary in (TEMP_SCRIPT, TEMP_WORKFLOW):
    if temporary.exists():
        temporary.unlink()
