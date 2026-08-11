#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import os
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

    def test_accepted_subject_flags_cannot_omit_helper_execution_custody(self) -> None:
        accepted_provenance = hashlib.sha256(PROVENANCE.read_bytes()).hexdigest()
        accepted_generated = hashlib.sha256(GENERATED.read_bytes()).hexdigest()
        for flag in (
            "require_accepted_private_review_commitment",
            "require_accepted_generated_subject",
        ):
            with self.subTest(flag=flag):
                guard, provenance_sentinel, generated_sentinel = self._guard_with_malicious_neighbors()
                # Remove unrelated subject-validation early exits. The invariant
                # under test is that either accepted-subject flag itself must
                # force provenance/generated helper custody *before* any later
                # input/subject work can run.
                guard._verify_accepted_generated_build_subject = lambda inputs: None
                guard._verify_accepted_private_review_commitment = lambda inputs: None
                previous_provenance = os.environ.get(guard.PROVENANCE_HELPER_ENV)
                previous_generated = os.environ.get(guard.GENERATED_BUILD_SUBJECT_HELPER_ENV)
                os.environ[guard.PROVENANCE_HELPER_ENV] = accepted_provenance
                os.environ[guard.GENERATED_BUILD_SUBJECT_HELPER_ENV] = accepted_generated
                try:
                    with self.assertRaises(guard.BuildGuardError):
                        guard.run_guarded_build(None, ["/usr/bin/true"], **{flag: True})
                finally:
                    if previous_provenance is None:
                        os.environ.pop(guard.PROVENANCE_HELPER_ENV, None)
                    else:
                        os.environ[guard.PROVENANCE_HELPER_ENV] = previous_provenance
                    if previous_generated is None:
                        os.environ.pop(guard.GENERATED_BUILD_SUBJECT_HELPER_ENV, None)
                    else:
                        os.environ[guard.GENERATED_BUILD_SUBJECT_HELPER_ENV] = previous_generated
                self.assertFalse(
                    provenance_sentinel.exists(),
                    "accepted-subject API flag executed a mutable provenance helper before accepted helper custody",
                )
                self.assertFalse(
                    generated_sentinel.exists(),
                    "accepted-subject API flag executed a mutable generated helper before accepted helper custody",
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
