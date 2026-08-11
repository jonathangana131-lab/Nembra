#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
import types
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
GUARD = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"
PROVENANCE = REPOSITORY / "Scripts/capture_tuya_private_input_provenance.py"
GENERATED = REPOSITORY / "Scripts/capture_cocoapods_generated_build_subject.py"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path.name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def raise_oserror(label: str):
    raise OSError(label)


class ExceptionProxyCustodyTests(unittest.TestCase):
    def _guard_with_malicious_neighbors(self):
        temporary = tempfile.TemporaryDirectory(prefix="nembra-exception-proxy-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        scripts = root / "Scripts"
        scripts.mkdir()
        shutil.copy2(GUARD, scripts / GUARD.name)

        provenance_sentinel = root / "provenance-executed.txt"
        generated_sentinel = root / "generated-executed.txt"
        (scripts / PROVENANCE.name).write_text(
            "from pathlib import Path\n"
            f"Path({str(provenance_sentinel)!r}).write_text('executed', encoding='utf-8')\n"
            "class ProvenanceError(Exception): pass\n",
            encoding="utf-8",
        )
        (scripts / GENERATED.name).write_text(
            "from pathlib import Path\n"
            f"Path({str(generated_sentinel)!r}).write_text('executed', encoding='utf-8')\n"
            "class GeneratedBuildSubjectError(Exception): pass\n",
            encoding="utf-8",
        )

        guard = load_module(scripts / GUARD.name, f"nembra_exception_proxy_{id(self)}")
        guard._parse_args = lambda argv: (None, ["/usr/bin/true"])
        return guard, provenance_sentinel, generated_sentinel

    def test_provenance_preaccept_failure_does_not_execute_mutable_neighbor_for_exception_matching(self) -> None:
        guard, provenance_sentinel, generated_sentinel = self._guard_with_malicious_neighbors()
        guard.provenance.require_accepted = lambda: raise_oserror("synthetic provenance descriptor failure")

        self.assertEqual(guard.main([]), 77)
        self.assertFalse(provenance_sentinel.exists())
        self.assertFalse(generated_sentinel.exists())

    def test_generated_preaccept_failure_does_not_execute_mutable_neighbor_for_exception_matching(self) -> None:
        guard, provenance_sentinel, generated_sentinel = self._guard_with_malicious_neighbors()

        class AcceptedProvenance(types.SimpleNamespace):
            class ProvenanceError(Exception):
                pass

        def accept_provenance():
            module = AcceptedProvenance()
            guard.provenance._module = module
            guard.provenance._accepted = True
            return module

        guard.provenance.require_accepted = accept_provenance
        guard.generated_build.require_accepted = lambda: raise_oserror("synthetic generated descriptor failure")

        self.assertEqual(guard.main([]), 77)
        self.assertFalse(provenance_sentinel.exists())
        self.assertFalse(generated_sentinel.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
