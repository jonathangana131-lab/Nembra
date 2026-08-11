#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BRANCH = "recovery/v14-field-compiler-window-2907-sol-20260811"
SOURCE_REPAIR_BRANCH = "repair/v14-field-tracked-source-window-sol-20260811"
SOURCE_REPAIR_HEAD = "31d94a4d8ecec04b960ccf219c7d48cdf5ae02d1"
PARENT_HEAD = "0eae2eb8a37f978ad2d42a7c06f9a3634d8297e6"
GUARD = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
AUTH_TEST = ROOT / "scripts/ci/tests/test_capture_field_tracked_source_window_authority.py"
CANONICAL_RED = ROOT / "scripts/ci/tests/test_capture_field_tracked_source_compiler_window_red_team.py"
VNODE_TEST = ROOT / "scripts/ci/tests/test_capture_cocoapods_vnode_attribute_custody.py"
PROVENANCE_TEST = ROOT / "scripts/ci/tests/test_capture_tuya_private_input_provenance.py"
SELF = Path(__file__)
TEMP_WORKFLOW = ROOT / ".github/workflows/tmp-v14-field-compiler-window-2907-recovery-sol.yml"
BYTECODE = (
    "Scripts/__pycache__/capture_tuya_private_input_provenance.cpython-312.pyc",
    "scripts/ci/__pycache__/es80_signed_field_artifact_private_runner.cpython-312.pyc",
    "scripts/ci/tests/__pycache__/test_capture_field_tracked_source_compiler_window_red_team.cpython-312.pyc",
    "scripts/ci/tests/__pycache__/test_capture_tuya_private_input_provenance.cpython-312.pyc",
)


def run(*argv: str) -> str:
    return subprocess.check_output(argv, cwd=ROOT, text=True).strip()


subprocess.run(
    ["/usr/bin/git", "merge-base", "--is-ancestor", PARENT_HEAD, "HEAD"],
    cwd=ROOT,
    check=True,
)
construction_delta = {
    line for line in run("git", "diff", "--name-only", f"{PARENT_HEAD}..HEAD").splitlines() if line
}
allowed_construction = {
    SELF.relative_to(ROOT).as_posix(),
    TEMP_WORKFLOW.relative_to(ROOT).as_posix(),
}
if not construction_delta or not construction_delta.issubset(allowed_construction):
    raise SystemExit(
        "recovery construction ancestry contains non-temporary drift before materialization: "
        + ", ".join(sorted(construction_delta))
    )
if run("git", "status", "--porcelain=v1", "--untracked-files=all"):
    raise SystemExit("construction checkout is not clean")

subprocess.run(
    [
        "/usr/bin/git", "fetch", "--no-tags", "origin",
        f"refs/heads/{SOURCE_REPAIR_BRANCH}:refs/remotes/origin/{SOURCE_REPAIR_BRANCH}",
    ],
    cwd=ROOT,
    check=True,
)
actual_repair = run("git", "rev-parse", f"refs/remotes/origin/{SOURCE_REPAIR_BRANCH}")
if actual_repair != SOURCE_REPAIR_HEAD:
    raise SystemExit(f"tracked-source repair branch moved: {actual_repair} != {SOURCE_REPAIR_HEAD}")

for path in (
    "Scripts/capture_tuya_private_input_build_guard.py",
    "scripts/ci/tests/test_capture_field_tracked_source_window_authority.py",
):
    payload = subprocess.check_output(
        ["/usr/bin/git", "show", f"{SOURCE_REPAIR_HEAD}:{path}"], cwd=ROOT
    )
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(payload)

installer = INSTALLER.read_text(encoding="utf-8")
old_invocation = '''run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE" \\\n    --lockfile "$ROOT/Podfile.lock" \\\n'''
new_invocation = '''run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE" \\\n    --accepted-source-root "$ROOT" \\\n    --accepted-source-sha "$SOURCE_SHA" \\\n    --lockfile "$ROOT/Podfile.lock" \\\n'''
if installer.count(old_invocation) != 1:
    raise SystemExit("#2907 guarded-build invocation drifted")
INSTALLER.write_text(installer.replace(old_invocation, new_invocation, 1), encoding="utf-8")

# Preserve #2878's attack primitive and closure invariant, but evolve its one
# historical pre-repair shape assertion now that accepted-source custody exists.
canonical = CANONICAL_RED.read_text(encoding="utf-8")
old_shape = '''    def test_current_field_build_is_endpoint_only_for_tracked_checkout_source(self) -> None:\n        installer = INSTALLER.read_text(encoding="utf-8")\n        guard = BUILD_GUARD.read_text(encoding="utf-8")\n\n        self.assertIn(\n            'verify_accepted_checkout_source "Private workspace bootstrap changed accepted-source inputs."',\n            installer,\n        )\n        self.assertIn(\n            'verify_accepted_checkout_source "Accepted-source inputs changed while the field build was compiling.',\n            installer,\n        )\n\n        start = installer.index('say "Building SDK-integrated Nembra Capture for the intended iPhone"')\n        end = installer.index('verify_private_tuya_inputs\\nverify_accepted_checkout_source', start)\n        build_window = installer[start:end]\n        self.assertIn('run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE"', build_window)\n        self.assertIn('-workspace NembraCapture.xcworkspace', build_window)\n\n        self.assertIn("def _watch_paths(inputs: PrivateInputs)", guard)\n        self.assertIn("generated CocoaPods workspace tree", guard)\n        self.assertNotIn("accepted_source_root", guard)\n        self.assertNotIn("accepted_source_sha", guard)\n\n'''
new_shape = '''    def test_current_field_build_holds_tracked_checkout_source_through_guard(self) -> None:\n        installer = INSTALLER.read_text(encoding="utf-8")\n        guard = BUILD_GUARD.read_text(encoding="utf-8")\n\n        self.assertIn(\n            'verify_accepted_checkout_source "Private workspace bootstrap changed accepted-source inputs."',\n            installer,\n        )\n        self.assertIn(\n            'verify_accepted_checkout_source "Accepted-source inputs changed while the field build was compiling.',\n            installer,\n        )\n\n        start = installer.index('say "Building SDK-integrated Nembra Capture for the intended iPhone"')\n        end = installer.index('verify_private_tuya_inputs\\nverify_accepted_checkout_source', start)\n        build_window = installer[start:end]\n        self.assertIn('run_accepted_source_python "$TUYA_BUILD_WINDOW_GUARD_RELATIVE"', build_window)\n        self.assertIn('--accepted-source-root "$ROOT"', build_window)\n        self.assertIn('--accepted-source-sha "$SOURCE_SHA"', build_window)\n        self.assertIn('-workspace NembraCapture.xcworkspace', build_window)\n\n        self.assertIn("def _accepted_tracked_source_manifest", guard)\n        self.assertIn("def _verify_tracked_source_manifest", guard)\n        self.assertIn("def _tracked_source_watch_paths", guard)\n        self.assertIn("accepted_source_root", guard)\n        self.assertIn("accepted_source_sha", guard)\n        self.assertIn("KQ_NOTE_ATTRIB", guard)\n\n'''
if canonical.count(old_shape) != 1:
    raise SystemExit("canonical #2878 pre-repair shape assertion drifted")
canonical = canonical.replace(old_shape, new_shape, 1)
canonical = canonical.replace(
    '"""V14 expected-red attack witness for tracked checkout source during field xcodebuild."""',
    '"""V14 attack witness and closure regression for tracked source during field xcodebuild."""',
    1,
)
CANONICAL_RED.write_text(canonical, encoding="utf-8")

for relative in BYTECODE:
    path = ROOT / relative
    if not path.is_file():
        raise SystemExit(f"expected accidental bytecode is missing: {relative}")
    subprocess.run(["/usr/bin/git", "rm", "--", relative], cwd=ROOT, check=True)

subprocess.run(["/usr/bin/python3", "-m", "py_compile", str(GUARD), str(AUTH_TEST), str(CANONICAL_RED), str(VNODE_TEST), str(PROVENANCE_TEST)], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/python3", str(AUTH_TEST)], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/python3", str(CANONICAL_RED)], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/python3", str(VNODE_TEST)], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/python3", str(PROVENANCE_TEST)], cwd=ROOT, check=True)
subprocess.run(["/bin/bash", "-n", str(INSTALLER)], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/git", "diff", "--check"], cwd=ROOT, check=True)

source = GUARD.read_text(encoding="utf-8")
for marker in (
    "def _accepted_tracked_source_manifest",
    "def _verify_tracked_source_manifest",
    "def _tracked_source_watch_paths",
    "require_accepted_tracked_source=True",
    "KQ_NOTE_ATTRIB",
):
    if marker not in source:
        raise SystemExit(f"missing repaired guard marker: {marker}")
installer = INSTALLER.read_text(encoding="utf-8")
for marker in ('--accepted-source-root "$ROOT"', '--accepted-source-sha "$SOURCE_SHA"'):
    if marker not in installer:
        raise SystemExit(f"missing accepted tracked-source CLI marker: {marker}")

for relative in BYTECODE:
    subprocess.run(["/usr/bin/git", "rm", "-f", "--ignore-unmatch", "--", relative], cwd=ROOT, check=True)

SELF.unlink()
subprocess.run(
    [
        "/usr/bin/git", "add",
        "Scripts/capture_tuya_private_input_build_guard.py",
        "scripts/field/install_one_time_capture.command",
        "scripts/ci/tests/test_capture_field_tracked_source_window_authority.py",
        "scripts/ci/tests/test_capture_field_tracked_source_compiler_window_red_team.py",
        str(SELF.relative_to(ROOT)),
    ],
    cwd=ROOT,
    check=True,
)
subprocess.run(["/usr/bin/git", "diff", "--cached", "--check"], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/git", "config", "user.name", "nembra-sol-bot"], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/git", "config", "user.email", "nembra-sol-bot@users.noreply.github.com"], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/git", "commit", "-m", "Recover tracked source compiler-window authority"], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/git", "push", "origin", f"HEAD:{BRANCH}"], cwd=ROOT, check=True)
