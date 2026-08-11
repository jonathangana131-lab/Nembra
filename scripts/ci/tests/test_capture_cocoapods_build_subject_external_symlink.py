#!/usr/bin/env python3
"""Expected-red: generated CocoaPods subject must bind followed symlink target bytes.

A CocoaPods-generated symlink may legitimately be represented inside the generated
build graph, but the graph digest cannot treat the symlink pathname/target string
as sufficient authority when Xcode can follow that link into mutable ignored
repository state. Any such external target must either be rejected or have its
consumed bytes covered by an independently admitted subject.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER = REPOSITORY / "Scripts" / "capture_cocoapods_build_subject.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("capture_cocoapods_build_subject", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("generated build-subject helper could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CocoaPodsGeneratedSymlinkTargetCustodyTests(unittest.TestCase):
    def test_mutable_ignored_symlink_target_cannot_preserve_subject_digest(self) -> None:
        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-cocoapods-symlink-subject-") as directory:
            root = Path(directory)
            (root / "Podfile.lock").write_text("PODS:\n  - ThingSmartHomeKit (7.8.0)\n", encoding="utf-8")
            (root / "Pods").mkdir()
            (root / "NembraCapture.xcworkspace").mkdir()

            # LocalSecrets/ is intentionally ignored by the real field checkout.
            # This path is deliberately outside the two private input trees that
            # current Tuya provenance separately fingerprints.
            external = root / "LocalSecrets" / "UnreviewedGeneratedInput" / "mutable.bin"
            external.parent.mkdir(parents=True)
            external.write_bytes(b"GRAPH_A")

            generated_link = root / "Pods" / "InjectedBuildInput.bin"
            generated_link.symlink_to("../LocalSecrets/UnreviewedGeneratedInput/mutable.bin")

            first = helper.fingerprint(root)
            external.write_bytes(b"GRAPH_B")
            second = helper.fingerprint(root)

            self.assertNotEqual(
                first,
                second,
                "generated build-subject digest ignored bytes reachable through a repo-internal symlink; "
                "reject external generated symlinks or bind every followed target to an independently admitted subject",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
