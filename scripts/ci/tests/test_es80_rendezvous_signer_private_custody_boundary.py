from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
WRAPPER = ROOT / "scripts/ci/es80_sign_field_authorization_from_rendezvous.py"
V16_WORKFLOW = ROOT / ".github/workflows/capture-v16-standalone.yml"
PRODUCTION_SURFACES = (
    ROOT / "scripts/field/install_one_time_capture.command",
    ROOT / "docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md",
    ROOT / "docs/ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md",
)


class RendezvousSignerPrivateCustodyBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.wrapper = WRAPPER.read_text(encoding="utf-8")

    def test_wrapper_freezes_all_key_visible_python_sources_from_git_objects(self) -> None:
        for required in (
            "accepted_execution_bundle",
            'GIT = Path("/usr/bin/git")',
            'PYTHON = Path("/usr/bin/python3")',
            '"GIT_NO_REPLACE_OBJECTS": "1"',
            '"GIT_CONFIG_GLOBAL": "/dev/null"',
            '"cat-file", "blob"',
            "_git_blob_sha(blob) != blob_id",
            "worktree != blob",
            '"PYTHONNOUSERSITE": "1"',
            '"PYTHONPATH": ""',
        ):
            with self.subTest(required=required):
                self.assertIn(required, self.wrapper)
        for source_name in (
            "es80_sign_field_authorization_from_rendezvous.py",
            "es80_field_authorization_rendezvous.py",
            "es80_field_authorization_envelope.py",
            "es80_signed_field_artifact_evidence.py",
        ):
            with self.subTest(source_name=source_name):
                self.assertIn(source_name, self.wrapper)
        self.assertNotIn("sys.executable,", self.wrapper)
        self.assertNotIn("str(SIGNER)", self.wrapper)

    def test_wrapper_is_still_not_promoted_by_unreviewed_production_surfaces(self) -> None:
        # Exact source custody closes the mutable-code/private-key defect, but field/private runbooks
        # stay conservative until trust-root review and the full app authority chain are accepted.
        wrapper_name = WRAPPER.name
        for surface in PRODUCTION_SURFACES:
            with self.subTest(surface=str(surface.relative_to(ROOT))):
                text = surface.read_text(encoding="utf-8")
                self.assertNotIn(wrapper_name, text)

    def test_wrapper_does_not_duplicate_stable_signing_subjects_from_cli(self) -> None:
        for forbidden in (
            "--bundle-identifier", "--source-commit-sha", "--build-identifier",
            "--build-instance-id", "--executable-sha256", "--info-plist-sha256",
            "--tuya-dependency-lock-sha256", "--external-build-record-sha256",
            "--signed-build-evidence-sha256", "--final-go-record-sha256",
            "--intended-device-pseudonym-sha256",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, self.wrapper)
        self.assertIn("--signed-evidence", self.wrapper)

    def test_v16_exact_head_gate_explicitly_runs_container_rendezvous_contracts(self) -> None:
        workflow = V16_WORKFLOW.read_text(encoding="utf-8")
        for required_filter in (
            "AuthenticatedStationaryCaptureAuthorizationInboxTests",
            "AuthenticatedStationaryCaptureSignerRendezvousDocumentTests",
            "AuthenticatedStationaryCaptureSignerRendezvousOutboxTests",
        ):
            with self.subTest(required_filter=required_filter):
                self.assertIn(f"swift test --filter {required_filter}", workflow)


if __name__ == "__main__":
    unittest.main()
