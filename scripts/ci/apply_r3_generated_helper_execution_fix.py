#!/usr/bin/env python3
"""Temporary deterministic patcher for #2775; self-deleted after green validation."""
from __future__ import annotations

from pathlib import Path

PRODUCTION = Path("scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py")
TESTS = Path("scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_final_go.py")
REGRESSION = Path("scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py")
WORKFLOW = Path(".github/workflows/capture-authenticated-stationary-generated-subject-final-go.yml")
SELF = Path("scripts/ci/apply_r3_generated_helper_execution_fix.py")
AUTOPATCH = Path(".github/workflows/capture-r3-generated-helper-execution-autopatch.yml")


def exactly_once(text: str, needle: str, label: str) -> None:
    count = text.count(needle)
    if count != 1:
        raise SystemExit(f"{label} anchor count drifted: {count}")


def patch_production() -> None:
    text = PRODUCTION.read_text(encoding="utf-8")
    import_anchor = "import argparse\nimport contextlib\nimport importlib.util\n"
    exactly_once(text, import_anchor, "production imports")
    text = text.replace(
        import_anchor,
        "import argparse\nimport contextlib\nimport hashlib\nimport importlib.util\n",
        1,
    )
    sys_anchor = "import subprocess\nimport sys\n"
    exactly_once(text, sys_anchor, "production sys import")
    text = text.replace(sys_anchor, "import subprocess\nimport sys\nimport types\n", 1)

    start_marker = "def _current_generated_subject(root: Path) -> str:\n"
    end_marker = "\n\ndef candidate_generated_authority(\n"
    start = text.find(start_marker)
    end = text.find(end_marker, start)
    if start < 0 or end < 0:
        raise SystemExit("mutable helper execution function anchors drifted")
    replacement = '''def _git_blob_oid(payload: bytes, accepted_oid: str) -> str:\n    header = b"blob " + str(len(payload)).encode("ascii") + b"\\0"\n    if len(accepted_oid) == 40:\n        return hashlib.sha1(header + payload).hexdigest()\n    if len(accepted_oid) == 64:\n        return hashlib.sha256(header + payload).hexdigest()\n    raise GeneratedSubjectGoError("accepted generated-helper Git object ID has unsupported width")\n\n\ndef _accepted_generated_helper_bytes(root: Path, source: str, base: Any) -> bytes:\n    accepted_oid = base.git(root, "rev-parse", f"{source}:{GENERATED_HELPER_PATH}").lower()\n    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", accepted_oid):\n        raise GeneratedSubjectGoError("accepted generated-helper Git blob identity is invalid")\n    payload = base.git_bytes(root, "show", f"{source}:{GENERATED_HELPER_PATH}")\n    if not isinstance(payload, bytes) or not payload or len(payload) > 2 * 1024 * 1024:\n        raise GeneratedSubjectGoError("accepted generated-helper Git blob has invalid bounded bytes")\n    if _git_blob_oid(payload, accepted_oid) != accepted_oid:\n        raise GeneratedSubjectGoError("generated-helper execution bytes do not match accepted Git blob")\n    return payload\n\n\ndef _current_generated_subject(root: Path, source: str, base: Any) -> str:\n    payload = _accepted_generated_helper_bytes(root, source, base)\n    module = types.ModuleType("nembra_accepted_cocoapods_generated_build_subject")\n    module.__file__ = f"{source}:{GENERATED_HELPER_PATH}"\n    module.__package__ = ""\n    try:\n        code = compile(payload, module.__file__, "exec", dont_inherit=True)\n        exec(code, module.__dict__)\n    except Exception as error:\n        raise GeneratedSubjectGoError("accepted generated-helper Git blob could not be evaluated") from error\n    if getattr(module, "SCHEMA", None) != GENERATED_SCHEMA.encode("ascii"):\n        raise GeneratedSubjectGoError("accepted generated-helper schema does not match Final-GO authority")\n    build_subject = getattr(module, "build_subject", None)\n    if not callable(build_subject):\n        raise GeneratedSubjectGoError("accepted generated-helper Git blob lacks build_subject authority")\n    try:\n        value = build_subject(\n            lockfile=root / "Podfile.lock",\n            pods=root / "Pods",\n            workspace=root / "NembraCapture.xcworkspace",\n        )\n    except Exception as error:\n        raise GeneratedSubjectGoError("accepted generated-helper rejected the current CocoaPods subject") from error\n    if not isinstance(value, str) or not HEX64.fullmatch(value) or value != value.lower():\n        raise GeneratedSubjectGoError("generated CocoaPods build subject could not be re-derived exactly")\n    return value\n'''
    text = text[:start] + replacement + text[end:]

    old_type = "derive_subject: Callable[[Path], str] = _current_generated_subject"
    if text.count(old_type) != 2:
        raise SystemExit(f"derive_subject type anchor count drifted: {text.count(old_type)}")
    text = text.replace(
        old_type,
        "derive_subject: Callable[[Path, str, Any], str] = _current_generated_subject",
    )
    exactly_once(text, "current = derive_subject(root)\n", "derive_subject invocation")
    text = text.replace(
        "current = derive_subject(root)\n",
        "current = derive_subject(root, source, base)\n",
        1,
    )
    child_anchor = '    "scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_workflow_gates.py",\n'
    exactly_once(text, child_anchor, "child authority regression list")
    text = text.replace(
        child_anchor,
        child_anchor + '    "scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py",\n',
        1,
    )
    PRODUCTION.write_text(text, encoding="utf-8")


def patch_existing_tests() -> None:
    text = TESTS.read_text(encoding="utf-8")
    text = text.replace("derive_subject=lambda _: DIGEST", "derive_subject=lambda *_: DIGEST")
    text = text.replace("derive_subject=lambda _: \"ef\" * 32", "derive_subject=lambda *_: \"ef\" * 32")
    if "derive_subject=lambda _:" in text:
        raise SystemExit("old one-argument derive_subject fixture remains")
    TESTS.write_text(text, encoding="utf-8")


def write_regression() -> None:
    REGRESSION.write_text('''#!/usr/bin/env python3\n"""Regression: Final-GO executes accepted helper Git bytes, never mutable worktree helper bytes."""\nfrom __future__ import annotations\n\nimport importlib.util\nimport subprocess\nimport tempfile\nimport unittest\nfrom pathlib import Path\n\nMODULE = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_generated_subject_final_go.py"\nSPEC = importlib.util.spec_from_file_location("generated_subject_final_go", MODULE)\nif SPEC is None or SPEC.loader is None:\n    raise RuntimeError("could not load generated-subject Final-GO R3 child")\nGO = importlib.util.module_from_spec(SPEC)\nSPEC.loader.exec_module(GO)\n\n\nclass GeneratedSubjectHelperExecutionCustodyTests(unittest.TestCase):\n    def _fixture(self, root: Path, output: str):\n        repository = root / "candidate"\n        repository.mkdir()\n        subprocess.run(["/usr/bin/git", "-C", str(repository), "init", "-q"], check=True)\n        subprocess.run(["/usr/bin/git", "-C", str(repository), "config", "user.email", "capture@nembra.invalid"], check=True)\n        subprocess.run(["/usr/bin/git", "-C", str(repository), "config", "user.name", "Nembra Capture QA"], check=True)\n        helper = repository / GO.GENERATED_HELPER_PATH\n        helper.parent.mkdir(parents=True, exist_ok=True)\n        helper.write_text(\n            "#!/usr/bin/env python3\\n"\n            "from pathlib import Path\\n"\n            f"SCHEMA = {GO.GENERATED_SCHEMA.encode()!r}\\n"\n            "class GeneratedBuildSubjectError(RuntimeError):\\n    pass\\n"\n            "def build_subject(*, lockfile: Path, pods: Path, workspace: Path) -> str:\\n"\n            "    assert lockfile.name == 'Podfile.lock'\\n"\n            "    assert pods.name == 'Pods'\\n"\n            "    assert workspace.name == 'NembraCapture.xcworkspace'\\n"\n            f"    return {output!r}\\n",\n            encoding="utf-8",\n        )\n        (repository / "Podfile.lock").write_text("PODS:\\n", encoding="utf-8")\n        (repository / "Pods").mkdir()\n        (repository / "NembraCapture.xcworkspace").mkdir()\n        subprocess.run(["/usr/bin/git", "-C", str(repository), "add", "."], check=True)\n        subprocess.run(["/usr/bin/git", "-C", str(repository), "commit", "-qm", "accepted fixture"], check=True)\n        source = subprocess.check_output(["/usr/bin/git", "-C", str(repository), "rev-parse", "HEAD"], text=True).strip()\n        return repository, source, GO._load_base_module()\n\n    def test_exact_accepted_helper_git_blob_executes_in_memory(self) -> None:\n        with tempfile.TemporaryDirectory(prefix="nembra-r3-helper-git-green-") as temporary:\n            expected = "b" * 64\n            repository, source, base = self._fixture(Path(temporary), expected)\n            self.assertEqual(GO._current_generated_subject(repository, source, base), expected)\n            self.assertEqual(subprocess.check_output(["/usr/bin/git", "-C", str(repository), "status", "--porcelain=v1", "--untracked-files=all"], text=True), "")\n\n    def test_mutable_worktree_helper_substitution_cannot_control_execution(self) -> None:\n        with tempfile.TemporaryDirectory(prefix="nembra-r3-helper-git-swap-") as temporary:\n            accepted_output = "b" * 64\n            attacker_output = "a" * 64\n            repository, source, base = self._fixture(Path(temporary), accepted_output)\n            helper = repository / GO.GENERATED_HELPER_PATH\n            accepted_bytes = helper.read_bytes()\n            helper.write_text(\n                "#!/usr/bin/env python3\\n"\n                f"SCHEMA = {GO.GENERATED_SCHEMA.encode()!r}\\n"\n                "def build_subject(**kwargs):\\n"\n                f"    return {attacker_output!r}\\n",\n                encoding="utf-8",\n            )\n            self.assertNotEqual(helper.read_bytes(), accepted_bytes)\n            self.assertEqual(\n                GO._current_generated_subject(repository, source, base),\n                accepted_output,\n                "mutable worktree helper bytes influenced accepted Git execution subject",\n            )\n            helper.write_bytes(accepted_bytes)\n            self.assertEqual(subprocess.check_output(["/usr/bin/git", "-C", str(repository), "status", "--porcelain=v1", "--untracked-files=all"], text=True), "")\n\n\nif __name__ == "__main__":\n    unittest.main(verbosity=2)\n''', encoding="utf-8")


def patch_workflow() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    path_anchor = "      - scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_workflow_gates.py\n"
    if text.count(path_anchor) != 2:
        raise SystemExit(f"workflow path anchor count drifted: {text.count(path_anchor)}")
    text = text.replace(
        path_anchor,
        path_anchor + "      - scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py\n",
    )
    compile_anchor = "            scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_workflow_gates.py\n"
    exactly_once(text, compile_anchor, "workflow compile list")
    text = text.replace(
        compile_anchor,
        "            scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_workflow_gates.py \\\n            scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py\n",
        1,
    )
    run_anchor = "          python3 scripts/ci/tests/test_es80_authenticated_stationary_generated_subject_workflow_gates.py\n"
    exactly_once(text, run_anchor, "workflow gate run")
    text = text.replace(
        run_anchor,
        run_anchor
        + "\n      - name: Prove generated helper executes from accepted Git bytes\n"
        + "        shell: bash\n"
        + "        run: |\n"
        + "          set -euo pipefail\n"
        + "          python3 scripts/ci/tests/test_es80_generated_subject_helper_execution_custody.py\n",
        1,
    )
    WORKFLOW.write_text(text, encoding="utf-8")


def main() -> int:
    patch_production()
    patch_existing_tests()
    write_regression()
    patch_workflow()
    AUTOPATCH.unlink()
    SELF.unlink()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
