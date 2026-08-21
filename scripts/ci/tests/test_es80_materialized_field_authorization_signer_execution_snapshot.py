#!/usr/bin/env python3
from pathlib import Path
import importlib.util
import os
import unittest

RUNNER_PATH = Path(__file__).resolve().parents[1] / "es80_run_materialized_field_authorization_signer.py"
SPEC = importlib.util.spec_from_file_location("materialized_signer_snapshot_runner", RUNNER_PATH)
assert SPEC and SPEC.loader
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class MaterializedSignerExecutionSnapshotTests(unittest.TestCase):
    def test_verified_module_loader_executes_exact_bytes_without_path_reopen(self) -> None:
        virtual = Path("/private/tmp/nembra-bundle/scripts/ci/frozen_fixture.py")
        module = runner._load_module(
            b'VALUE = 7\nCAPTURED_FILE = __file__\n',
            virtual,
            "nembra_frozen_fixture",
        )
        self.assertEqual(module.VALUE, 7)
        self.assertEqual(module.CAPTURED_FILE, str(virtual))

    def test_main_consumes_verified_source_bytes_before_private_key_delegation(self) -> None:
        source = RUNNER_PATH.read_text(encoding="utf-8")
        main = source[source.index("def main("):]
        snapshot = main.index("_snapshot_materialized_bundle(")
        wrapper_load = main.index("_load_module(")
        private_key = main.index('"--private-key"')
        signer_launch = main.index("_run_frozen_signer(")

        self.assertLess(snapshot, wrapper_load)
        self.assertLess(wrapper_load, private_key)
        self.assertLess(private_key, signer_launch)
        self.assertIn(
            "verified_sources[os.fspath(WRAPPER_RELATIVE_PATH)]",
            main,
        )
        self.assertIn(
            "verified_sources[os.fspath(RENDEZVOUS_RELATIVE_PATH)]",
            main,
        )
        self.assertNotIn(
            "_load_module(\n            bundle / WRAPPER_RELATIVE_PATH",
            main,
        )

    def test_signer_child_uses_inherited_anonymous_verified_sources(self) -> None:
        source = RUNNER_PATH.read_text(encoding="utf-8")
        launch_start = source.index("def _run_frozen_signer(")
        launch_end = source.index("\ndef parser()", launch_start)
        launch = source[launch_start:launch_end]

        self.assertIn("tempfile.TemporaryFile", source)
        self.assertIn("pass_fds=(signer_fd, evidence_fd)", launch)
        self.assertIn('cwd="/"', launch)
        self.assertIn('"-I", "-c", _FROZEN_SIGNER_BOOTSTRAP', launch)
        self.assertIn("verified_sources[os.fspath(SIGNER_RELATIVE_PATH)]", launch)
        self.assertIn("verified_sources[os.fspath(EVIDENCE_RELATIVE_PATH)]", launch)
        self.assertNotIn("bundle / SIGNER_RELATIVE_PATH,", launch)

    def test_frozen_child_preloads_evidence_before_compiling_signer(self) -> None:
        bootstrap = runner._FROZEN_SIGNER_BOOTSTRAP
        evidence_registration = bootstrap.index(
            'sys.modules["es80_signed_field_artifact_evidence"] = evidence'
        )
        signer_compile = bootstrap.index(
            'exec(compile(signer_source, signer_virtual, "exec"), namespace)'
        )
        private_main = bootstrap.index(
            'result = namespace["main"](sys.argv[1:])'
        )

        self.assertLess(evidence_registration, signer_compile)
        self.assertLess(signer_compile, private_main)
        self.assertIn('namespace["REPOSITORY_ROOT"] = Path(bundle_root)', bootstrap)
        self.assertIn('os.environ.pop("NEMBRA_SIGNER_SOURCE_FD")', bootstrap)
        self.assertIn('os.environ.pop("NEMBRA_EVIDENCE_SOURCE_FD")', bootstrap)

    def test_execution_snapshot_keeps_closed_manifest_source_order(self) -> None:
        self.assertEqual(
            runner.REQUIRED_EXECUTION_SOURCES,
            (
                os.fspath(runner.RUNNER_RELATIVE_PATH),
                os.fspath(runner.WRAPPER_RELATIVE_PATH),
                os.fspath(runner.RENDEZVOUS_RELATIVE_PATH),
                os.fspath(runner.SIGNER_RELATIVE_PATH),
                os.fspath(runner.EVIDENCE_RELATIVE_PATH),
            ),
        )


if __name__ == "__main__":
    unittest.main()
