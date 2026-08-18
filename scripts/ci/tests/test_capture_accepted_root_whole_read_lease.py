#!/usr/bin/env python3
"""Require strict accepted-root mode to plan the complete compiler input tree."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"

def load():
    spec = importlib.util.spec_from_file_location("nembra_whole_root_lease", ORCHESTRATOR)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def seed(root: Path) -> tuple[Path, ...]:
    (root / "NembraCapture.xcworkspace").mkdir(parents=True)
    (root / "NembraCapture.xcworkspace/contents.xcworkspacedata").write_text("<Workspace/>\n")
    (root / "Pods/Fixture").mkdir(parents=True)
    (root / "Pods/Fixture/pod.swift").write_text("// pod\n")
    (root / "Sources").mkdir()
    (root / "Sources/App.swift").write_text("let accepted = true\n")
    (root / "LocalSecrets/TuyaSDK").mkdir(parents=True)
    (root / "LocalSecrets/TuyaSDK/sdk.bin").write_bytes(b"sdk")
    (root / "LocalSecrets/TuyaRuntime").mkdir(parents=True)
    (root / "LocalSecrets/TuyaRuntime/runtime.bin").write_bytes(b"runtime")
    (root / "Podfile.lock").write_text("PODS:\n")
    return (
        root / "Podfile.lock",
        root / "NembraCapture.xcworkspace",
        root / "NembraCapture.xcworkspace/contents.xcworkspacedata",
        root / "Pods",
        root / "Pods/Fixture/pod.swift",
        root / "Sources/App.swift",
        root / "LocalSecrets/TuyaSDK/sdk.bin",
        root / "LocalSecrets/TuyaRuntime/runtime.bin",
    )

class WholeRootLeaseTests(unittest.TestCase):
    def test_repository_root_subject_recursively_plans_all_compiler_inputs(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-whole-root-", dir=REPOSITORY) as raw:
            root = Path(raw) / "accepted"
            root.mkdir()
            required = seed(root)
            plan = helper._lease_paths((root,), root)
            planned = {path for path, _host_only in plan}
            self.assertIn(root, planned)
            for path in required:
                self.assertIn(path, planned, path)

    def test_strict_source_shape_uses_one_complete_root_subject(self) -> None:
        source = ORCHESTRATOR.read_text(encoding="utf-8")
        strict = source[source.index("if accepted_generated_manifest_sha256 is not None:"):]
        self.assertIn("private_subjects = (accepted_root,)", strict)
        self.assertIn("lease_repo = accepted_root", strict)
        self.assertIn("build_cwd = accepted_root", strict)
        self.assertNotIn(
            "accepted_root / CANONICAL_SDK_RELATIVE,\n                accepted_root / CANONICAL_RUNTIME_RELATIVE,",
            strict,
        )

if __name__ == "__main__":
    unittest.main(verbosity=2)
