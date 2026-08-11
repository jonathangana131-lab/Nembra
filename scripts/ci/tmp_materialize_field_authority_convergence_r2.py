#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
GIT = "/usr/bin/git"
PREARM_BASE = "d0b134ca2a49edc029f114660dfb8e216ece682e"
PREARM_HEAD = "8553e0787092335d5681c36e538f039a5063274b"
PAYLOAD_HEAD = "1fb4628932e2dfee7333dee0f797c072dd934743"
PREARM_PATHS = (
    ".github/workflows/capture-field-untracked-prearm-injection-red-team.yml",
    "Scripts/capture_tuya_private_input_build_guard.py",
    "scripts/ci/tests/test_capture_field_untracked_prearm_injection_red_team.py",
)


def run(*args: str, input_bytes: bytes | None = None, capture: bool = False) -> bytes:
    result = subprocess.run(
        [GIT, "-C", str(ROOT), *args],
        input=input_bytes,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.decode("utf-8", errors="replace"))
    return result.stdout if capture else b""


patch = run("diff", PREARM_BASE, PREARM_HEAD, "--", *PREARM_PATHS, capture=True)
if not patch:
    raise SystemExit("#2924 pre-arm net patch is empty")
run("apply", "--3way", "--index", input_bytes=patch)

payload_materializer = run(
    "show",
    f"{PAYLOAD_HEAD}:scripts/ci/tmp_v14_field_git_payload_identity_materialize.py",
    capture=True,
)
with tempfile.NamedTemporaryFile(prefix="nembra-git-payload-", suffix=".py", delete=False) as temporary:
    temporary.write(payload_materializer)
    materializer_path = Path(temporary.name)
try:
    subprocess.run(["/usr/bin/python3", str(materializer_path)], cwd=ROOT, check=True)
finally:
    materializer_path.unlink(missing_ok=True)

# Advance only the source contracts whose stronger authority shapes were
# deliberately composed here. Do not weaken unrelated assertions.
git_authority_path = ROOT / "scripts/ci/tests/test_capture_field_installer_git_authority_red_team.py"
git_authority = git_authority_path.read_text(encoding="utf-8")
old_git_stream = "        self.assertIn('run_authority_git show \"$SOURCE_SHA:$relative_path\"', installer)\n"
new_git_stream = (
    "        self.assertIn('read_verified_accepted_git_blob \"$relative_path\" |', installer)\n"
    "        self.assertNotIn('run_authority_git show \"$SOURCE_SHA:$relative_path\" |', installer)\n"
)
if git_authority.count(old_git_stream) != 1:
    raise SystemExit(f"Git-authority direct-stream seam count={git_authority.count(old_git_stream)}")
git_authority_path.write_text(git_authority.replace(old_git_stream, new_git_stream, 1), encoding="utf-8")

provenance_path = ROOT / "scripts/ci/tests/test_capture_tuya_private_input_provenance.py"
provenance = provenance_path.read_text(encoding="utf-8")
old_build = '        build_call = "-- /usr/bin/xcodebuild"\n'
new_build = '        build_call = \'-- "$SELECTED_XCODEBUILD"\'\n'
if provenance.count(old_build) != 1:
    raise SystemExit(f"provenance selected-Xcode seam count={provenance.count(old_build)}")
provenance = provenance.replace(old_build, new_build, 1)
old_provenance_stream = "        self.assertIn('run_authority_git show \"$SOURCE_SHA:$relative_path\"', installer)\n"
new_provenance_stream = (
    "        self.assertIn('read_verified_accepted_git_blob \"$relative_path\" |', installer)\n"
    "        self.assertNotIn('run_authority_git show \"$SOURCE_SHA:$relative_path\" |', installer)\n"
)
if provenance.count(old_provenance_stream) != 1:
    raise SystemExit(f"provenance direct-stream seam count={provenance.count(old_provenance_stream)}")
provenance_path.write_text(
    provenance.replace(old_provenance_stream, new_provenance_stream, 1),
    encoding="utf-8",
)

print("materialized #2924 pre-arm + #2937 verified Git payload on current #2966 spine")
