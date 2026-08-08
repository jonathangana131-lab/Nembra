#!/usr/bin/env python3
from pathlib import Path

harness_path = Path("scripts/ci/xcode27_simulator_capture.sh")
workflow_path = Path(".github/workflows/capture-simulator-visual-custody-source.yml")

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

workflow = workflow_path.read_text(encoding="utf-8")
path_marker = "      - scripts/ci/tests/test_xcode27_simulator_visual_evidence_manifest_subject_custody_source.py\n"
path_addition = path_marker + "      - scripts/ci/tests/test_xcode27_simulator_visual_evidence_mutation_race_source.py\n"
if workflow.count(path_marker) != 1:
    raise SystemExit(f"visual custody workflow path marker count={workflow.count(path_marker)}")
if "test_xcode27_simulator_visual_evidence_mutation_race_source.py" not in workflow:
    workflow = workflow.replace(path_marker, path_addition, 1)

command_marker = '''          python3 -m py_compile scripts/ci/tests/test_xcode27_simulator_visual_evidence_manifest_subject_custody_source.py
          python3 scripts/ci/tests/test_xcode27_simulator_visual_evidence_manifest_subject_custody_source.py
'''
command_addition = command_marker + '''          python3 -m py_compile scripts/ci/tests/test_xcode27_simulator_visual_evidence_mutation_race_source.py
          python3 scripts/ci/tests/test_xcode27_simulator_visual_evidence_mutation_race_source.py
'''
if workflow.count(command_marker) != 1:
    raise SystemExit(f"visual custody workflow command marker count={workflow.count(command_marker)}")
if workflow.count("python3 scripts/ci/tests/test_xcode27_simulator_visual_evidence_mutation_race_source.py") == 0:
    workflow = workflow.replace(command_marker, command_addition, 1)
workflow_path.write_text(workflow, encoding="utf-8")

# Focused static acceptance of the exact production seam.
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

workflow = workflow_path.read_text(encoding="utf-8")
for token in (
    "test_xcode27_simulator_visual_evidence_mutation_race_source.py",
    "python3 scripts/ci/tests/test_xcode27_simulator_visual_evidence_mutation_race_source.py",
):
    if token not in workflow:
        raise SystemExit(f"exact-head source gate missing mutation-race regression: {token}")

print("nonblocking retained visual-evidence custody repair: PASS")
