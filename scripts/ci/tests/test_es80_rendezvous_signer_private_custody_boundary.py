from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
WRAPPER = ROOT / "scripts/ci/es80_sign_field_authorization_from_rendezvous.py"
PRODUCTION_SURFACES = (
    ROOT / "scripts/field/install_one_time_capture.command",
    ROOT / "docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md",
    ROOT / "docs/ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md",
)


class RendezvousSignerPrivateCustodyBoundaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.wrapper = WRAPPER.read_text(encoding="utf-8")

    def test_mutable_wrapper_self_identifies_as_nonproduction(self) -> None:
        # Until this wrapper is executed from independently accepted immutable helper/signer bytes,
        # handing a production private-key path to its checkout-selected signer is not accepted.
        self.assertIn("CI/research orchestration only", self.wrapper)
        self.assertIn("spec_from_file_location", self.wrapper)
        self.assertIn('SIGNER = HERE / "es80_field_authorization_envelope.py"', self.wrapper)
        self.assertIn("subprocess.run(build_signer_command", self.wrapper)

    def test_nonproduction_wrapper_is_not_a_field_or_private_signing_entrypoint(self) -> None:
        wrapper_name = WRAPPER.name
        for surface in PRODUCTION_SURFACES:
            with self.subTest(surface=str(surface.relative_to(ROOT))):
                text = surface.read_text(encoding="utf-8")
                self.assertNotIn(
                    wrapper_name,
                    text,
                    "Mutable rendezvous signing orchestration must not be promoted into a "
                    "field/private-key entrypoint before independently accepted source custody.",
                )

    def test_wrapper_does_not_duplicate_stable_signing_subjects_from_cli(self) -> None:
        # Stable source/build/evidence/device facts remain owned by the accepted signed-evidence
        # subject. The wrapper is allowed to supply only live-attempt chronology + challenge and
        # explicit custody paths to the existing signer.
        for forbidden in (
            "--bundle-identifier",
            "--source-commit-sha",
            "--build-identifier",
            "--build-instance-id",
            "--executable-sha256",
            "--info-plist-sha256",
            "--tuya-dependency-lock-sha256",
            "--external-build-record-sha256",
            "--signed-build-evidence-sha256",
            "--final-go-record-sha256",
            "--intended-device-pseudonym-sha256",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, self.wrapper)
        self.assertIn("--signed-evidence", self.wrapper)


if __name__ == "__main__":
    unittest.main()
