#!/usr/bin/env python3
from pathlib import Path
import textwrap

source_path = Path("scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py")
source = source_path.read_text(encoding="utf-8")

parent_line = 'PARENT_BRANCH = "control/v14-auth-stationary-final-go-sol"\n'
if source.count(parent_line) != 1:
    raise SystemExit("parent branch constant seam drifted")
source = source.replace(
    parent_line,
    parent_line
    + 'PARENT_SOURCE_COMMIT = "3fdd32551831c3469e0853ddcee8fa828d38b87b"\n'
    + 'PARENT_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_final_go.py"\n',
    1,
)

old_loader = textwrap.dedent('''\
def _load_base_module():
    path = Path(__file__).with_name("es80_authenticated_stationary_final_go.py")
    spec = importlib.util.spec_from_file_location("nembra_authenticated_stationary_final_go", path)
    if spec is None or spec.loader is None:
        raise GeneratedSubjectGoError("authenticated-stationary Final-GO parent could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
''')
new_loader = textwrap.dedent('''\
def _parent_git_environment() -> dict[str, str]:
    return {"PATH": "/usr/bin:/bin", "GIT_NO_REPLACE_OBJECTS": "1"}


def _accepted_parent_module_bytes(root: Path, source: str) -> bytes:
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", source):
        raise GeneratedSubjectGoError("accepted parent source identity is invalid")
    try:
        accepted_oid = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "rev-parse", f"{source}:{PARENT_MODULE_PATH}"],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=_parent_git_environment(),
        ).stdout.strip().lower()
        payload = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "cat-file", "blob", accepted_oid],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=_parent_git_environment(),
        ).stdout
        verified = subprocess.run(
            ["/usr/bin/git", "-C", str(root), "hash-object", "--stdin"],
            input=payload,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=_parent_git_environment(),
        ).stdout.decode("ascii").strip().lower()
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError) as error:
        raise GeneratedSubjectGoError("accepted parent Final-GO Git custody failed") from error
    if (
        not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", accepted_oid)
        or not payload
        or len(payload) > 4 * 1024 * 1024
        or verified != accepted_oid
        or _git_blob_oid(payload, accepted_oid) != accepted_oid
    ):
        raise GeneratedSubjectGoError("accepted parent Final-GO execution bytes failed Git identity verification")
    return payload


def _load_base_module():
    root = Path(__file__).resolve().parents[2]
    payload = _accepted_parent_module_bytes(root, PARENT_SOURCE_COMMIT)
    filename = f"git:{PARENT_SOURCE_COMMIT}:{PARENT_MODULE_PATH}"
    module = types.ModuleType("nembra_authenticated_stationary_final_go")
    module.__file__ = str(root / PARENT_MODULE_PATH)
    module.__package__ = ""
    try:
        exec(compile(payload, filename, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise GeneratedSubjectGoError("accepted parent Final-GO Git blob could not execute") from error
    return module
''')
if source.count(old_loader) != 1:
    raise SystemExit("mutable parent loader seam drifted")
source = source.replace(old_loader, new_loader, 1)

child_tail = '    "scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py",\n)'
if source.count(child_tail) != 1:
    raise SystemExit("child authority paths seam drifted")
source = source.replace(
    child_tail,
    '    "scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py",\n'
    '    "scripts/ci/tests/test_es80_generated_subject_base_module_execution_custody.py",\n)',
    1,
)

parent_sha_line = '    parent_sha = base.canon(parent_head.get("sha"), "parent Final-GO PR head")\n'
if source.count(parent_sha_line) != 1:
    raise SystemExit("parent SHA seam drifted")
source = source.replace(
    parent_sha_line,
    parent_sha_line
    + '    if parent_sha != PARENT_SOURCE_COMMIT:\n'
    + '        raise GeneratedSubjectGoError("generated-subject control plane parent moved beyond pinned execution authority")\n',
    1,
)
source_path.write_text(source, encoding="utf-8")

Path("scripts/ci/tests/test_es80_generated_subject_base_module_execution_custody.py").write_text(
    textwrap.dedent('''\
#!/usr/bin/env python3
"""Regression for R3 loading its authenticated-stationary base from accepted Git bytes."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
R3_SOURCE = REPOSITORY / "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
R3_RELATIVE = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
BASE_RELATIVE = "scripts/ci/es80_authenticated_stationary_final_go.py"


class GeneratedSubjectBaseModuleExecutionCustodyTests(unittest.TestCase):
    def test_hidden_base_worktree_replacement_never_executes_from_r3_loader(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-r3-base-module-exec-") as temporary:
            root = Path(temporary).resolve(strict=True)
            sentinel = root / "attacker-base-executed"
            r3 = root / R3_RELATIVE
            base = root / BASE_RELATIVE
            r3.parent.mkdir(parents=True, exist_ok=True)
            r3.write_bytes(R3_SOURCE.read_bytes())
            base.write_text("#!/usr/bin/env python3\\nBASE_MARKER = 'accepted'\\n", encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", "."], check=True)
            subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted R3/base fixture"], check=True)
            accepted_source = subprocess.check_output(["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
            accepted_blob = subprocess.check_output(["/usr/bin/git", "-C", str(root), "rev-parse", f"{accepted_source}:{BASE_RELATIVE}"], text=True).strip()
            subprocess.run(["/usr/bin/git", "-C", str(root), "update-index", "--assume-unchanged", BASE_RELATIVE], check=True)
            base.write_text(
                "#!/usr/bin/env python3\\nfrom pathlib import Path\\n"
                + f"Path({str(sentinel)!r}).write_text('executed', encoding='utf-8')\\n"
                + "BASE_MARKER = 'substituted'\\n",
                encoding="utf-8",
            )
            current_blob = subprocess.check_output(["/usr/bin/git", "-C", str(root), "hash-object", "--no-filters", "--", BASE_RELATIVE], text=True).strip()
            self.assertNotEqual(current_blob, accepted_blob)
            self.assertEqual(subprocess.check_output(["/usr/bin/git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"], text=True), "")
            previous = sys.dont_write_bytecode
            sys.dont_write_bytecode = True
            try:
                spec = importlib.util.spec_from_file_location("r3_loader_fixture", r3)
                if spec is None or spec.loader is None:
                    self.fail("could not load R3 fixture")
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                module.PARENT_SOURCE_COMMIT = accepted_source
                loaded = module._load_base_module()
            finally:
                sys.dont_write_bytecode = previous
            self.assertFalse(sentinel.exists(), "R3 executed mutable authenticated-stationary base worktree bytes before exact parent authority was established")
            self.assertEqual(getattr(loaded, "BASE_MARKER", None), "accepted")


if __name__ == "__main__":
    unittest.main(verbosity=2)
'''),
    encoding="utf-8",
)

workflow_path = Path(".github/workflows/capture-authenticated-stationary-generated-subject-final-go.yml")
workflow = workflow_path.read_text(encoding="utf-8")
trigger = "      - scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py\n"
if workflow.count(trigger) != 2:
    raise SystemExit("canonical workflow trigger seam drifted")
workflow = workflow.replace(trigger, trigger + "      - scripts/ci/tests/test_es80_generated_subject_base_module_execution_custody.py\n")
compile_tail = "            scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py\n"
if workflow.count(compile_tail) != 1:
    raise SystemExit("canonical workflow compile seam drifted")
workflow = workflow.replace(
    compile_tail,
    "            scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py \\\n"
    "            scripts/ci/tests/test_es80_generated_subject_base_module_execution_custody.py\n",
    1,
)
run_tail = textwrap.dedent('''\
      - name: Prove generated helper executes from accepted Git bytes
        shell: bash
        run: |
          set -euo pipefail
          python3 scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py
''')
if workflow.count(run_tail) != 1:
    raise SystemExit("canonical workflow run seam drifted")
workflow = workflow.replace(
    run_tail,
    run_tail
    + textwrap.dedent('''\

      - name: Prove authenticated-stationary parent executes from accepted Git bytes
        shell: bash
        run: |
          set -euo pipefail
          python3 scripts/ci/tests/test_es80_generated_subject_base_module_execution_custody.py
'''),
    1,
)
workflow_path.write_text(workflow, encoding="utf-8")

Path(".github/workflows/tmp-v14-r3-parent-module-execution-materialize.yml").unlink()
Path("scripts/ci/tmp_materialize_r3_parent_execution.py").unlink()
