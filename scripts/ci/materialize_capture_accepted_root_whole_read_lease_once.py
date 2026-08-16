#!/usr/bin/env python3
"""One-shot authoring helper for the whole accepted-root compiler read lease repair."""

from pathlib import Path
import textwrap

ROOT = Path(__file__).resolve().parents[2]


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return source.replace(old, new, 1)


orchestrator = ROOT / "scripts/ci/capture_selected_xcode_build_orchestrator.py"
source = orchestrator.read_text(encoding="utf-8")
source = replace_once(
    source,
    '''            private_subjects = (
                accepted_root / CANONICAL_SDK_RELATIVE,
                accepted_root / CANONICAL_RUNTIME_RELATIVE,
            )
            lease_repo = accepted_root
            build_cwd = accepted_root
''',
    '''            # Strict accepted-root mode must make the entire sealed compiler-input
            # tree readable to the exact dedicated build identity. The parent container
            # remains the lease repository so the accepted root itself is a descriptor-
            # pinned subject rather than being rejected as the repository root.
            private_subjects = (accepted_root,)
            lease_repo = accepted_root.parent
            build_cwd = accepted_root
''',
    "strict accepted-root lease topology",
)
orchestrator.write_text(source, encoding="utf-8")

composition = ROOT / "scripts/ci/tests/test_capture_accepted_root_build_composition.py"
test_source = composition.read_text(encoding="utf-8")
test_source = replace_once(
    test_source,
    '''            self.assertEqual(
                lease.subjects,
                (
                    accepted_root / helper.CANONICAL_SDK_RELATIVE,
                    accepted_root / helper.CANONICAL_RUNTIME_RELATIVE,
                ),
            )
            self.assertEqual(lease.repo, accepted_root)
''',
    '''            self.assertEqual(lease.subjects, (accepted_root,))
            self.assertEqual(lease.repo, accepted_root.parent)
''',
    "strict composition lease assertion",
)
composition.write_text(test_source, encoding="utf-8")

focused = textwrap.dedent(r'''#!/usr/bin/env python3
"""Inverse regression for whole accepted-root compiler read/search authority."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location(
        "nembra_accepted_root_whole_read_lease_repair", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AcceptedRootWholeReadLeaseRepairTests(unittest.TestCase):
    def test_whole_root_subject_covers_tracked_generated_and_private_inputs(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-whole-root-read-") as temporary:
            container = Path(temporary) / "custody-container"
            accepted = container / "root"
            accepted.mkdir(parents=True)
            required = [
                accepted / "Podfile.lock",
                accepted / "NembraCapture.xcworkspace/contents.xcworkspacedata",
                accepted / "Pods/Manifest.lock",
                accepted / "NembraCapture/App.swift",
                accepted / "LocalSecrets/TuyaSDK/Build/ThingSmartCryption.framework/fixture",
                accepted / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig/Config.swift",
            ]
            for path in required:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("fixture\n", encoding="utf-8")

            plan = helper._lease_paths((accepted,), container)
            planned = {path: host_only for path, host_only in plan}
            self.assertIn(container, planned)
            self.assertFalse(planned[container])
            self.assertIn(accepted, planned)
            self.assertFalse(planned[accepted])
            for path in required:
                with self.subTest(path=path):
                    self.assertIn(path, planned)
                    self.assertFalse(planned[path])

            file_acl = helper._acl_text("nembrabuildfixture", False, False)
            directory_acl = helper._acl_text("nembrabuildfixture", True, False)
            self.assertIn("read", file_acl)
            self.assertIn("list,search", directory_acl)
            self.assertNotIn("write", file_acl)
            self.assertNotIn("write", directory_acl)

    def test_old_private_subtree_topology_does_not_cover_workspace_or_pods(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-subtree-read-") as temporary:
            accepted = Path(temporary) / "root"
            sdk = accepted / helper.CANONICAL_SDK_RELATIVE
            runtime = accepted / helper.CANONICAL_RUNTIME_RELATIVE
            workspace = accepted / "NembraCapture.xcworkspace/contents.xcworkspacedata"
            pods = accepted / "Pods/Manifest.lock"
            sdk.mkdir(parents=True)
            runtime.mkdir(parents=True)
            for path in (workspace, pods):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("fixture\n", encoding="utf-8")
            plan = helper._lease_paths((sdk, runtime), accepted)
            planned = {path for path, _host_only in plan}
            self.assertNotIn(workspace, planned)
            self.assertNotIn(pods, planned)


if __name__ == "__main__":
    unittest.main(verbosity=2)
''')
(ROOT / "scripts/ci/tests/test_capture_accepted_root_whole_read_lease_repair.py").write_text(
    focused, encoding="utf-8"
)
