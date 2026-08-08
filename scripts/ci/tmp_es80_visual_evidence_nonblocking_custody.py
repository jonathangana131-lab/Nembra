#!/usr/bin/env python3
from pathlib import Path

harness_path = Path("scripts/ci/xcode27_simulator_capture.sh")
harness = harness_path.read_text(encoding="utf-8")

old_flags = '''O_DIRECTORY = getattr(os, "O_DIRECTORY", 0)
O_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
O_CLOEXEC = getattr(os, "O_CLOEXEC", 0)
if O_DIRECTORY == 0 or O_NOFOLLOW == 0:
    raise SystemExit("visual evidence custody requires O_DIRECTORY and O_NOFOLLOW")
'''
new_flags = '''O_DIRECTORY = getattr(os, "O_DIRECTORY", 0)
O_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
O_NONBLOCK = getattr(os, "O_NONBLOCK", 0)
O_CLOEXEC = getattr(os, "O_CLOEXEC", 0)
if O_DIRECTORY == 0 or O_NOFOLLOW == 0 or O_NONBLOCK == 0:
    raise SystemExit("visual evidence custody requires O_DIRECTORY, O_NOFOLLOW, and O_NONBLOCK")
'''
if harness.count(old_flags) != 1:
    raise SystemExit(f"visual custody capability marker count={harness.count(old_flags)}")
harness = harness.replace(old_flags, new_flags, 1)

old_file_flags = "FILE_FLAGS = os.O_RDONLY | O_NOFOLLOW | O_CLOEXEC\n"
new_file_flags = "FILE_FLAGS = os.O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC\n"
if harness.count(old_file_flags) != 1:
    raise SystemExit(f"retained FILE_FLAGS marker count={harness.count(old_file_flags)}")
harness = harness.replace(old_file_flags, new_file_flags, 1)
harness_path.write_text(harness, encoding="utf-8")

harness = harness_path.read_text(encoding="utf-8")
marker = 'VISUAL_EVIDENCE_MANIFEST="$ARTIFACTS_DIR/NembraCaptureSimulatorVisualEvidence.json"'
visual = harness[harness.index(marker):]
for token in (
    'O_NONBLOCK = getattr(os, "O_NONBLOCK", 0)',
    'FILE_FLAGS = os.O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC',
    'st_nlink',
    'directory changed during enumeration',
    'artifact root changed during visual-evidence enumeration',
    'os.O_EXCL',
    'dir_fd=artifacts_fd',
    'hashlib.sha256(manifest_bytes).hexdigest()',
):
    if token not in visual:
        raise SystemExit(f"visual mutation-race repair missing: {token}")
if visual.count("os.fstat(") < 6:
    raise SystemExit("visual mutation-race repair lost descriptor pre/post proof")

print("nonblocking retained visual-evidence harness repair: PASS")
