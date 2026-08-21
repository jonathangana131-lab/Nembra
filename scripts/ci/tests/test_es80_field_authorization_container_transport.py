#!/usr/bin/env python3
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/field/transfer_field_authorization.command"


class FieldAuthorizationContainerTransportSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = SCRIPT.read_text(encoding="utf-8")

    def test_direct_self_test_executes_before_device_or_platform_gate(self) -> None:
        completed = subprocess.run(
            [str(SCRIPT), "--self-test"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertIn(
            "FIELD_AUTHORIZATION_TRANSPORT_SELF_TEST_OK_NOT_PHYSICAL_GO",
            completed.stdout,
        )
        self.assertEqual(completed.stderr, "")

    def test_transport_is_fixed_to_capture_container_contract(self) -> None:
        for token in (
            'BUNDLE_ID="com.jonathangana131.nembra.capturelearn"',
            'DOMAIN_TYPE="appDataContainer"',
            'NembraCapture/FieldAuthorization',
            'retained-install-manifest.json',
            'signer-rendezvous.json',
            'authorization-envelope.json',
            'xcode27_devicectl_manifest_transport_contract.sh',
        ):
            self.assertIn(token, self.source)
        self.assertNotIn("NEMBRA_FIELD_BUNDLE_ID", self.source)
        self.assertNotIn("NEMBRA_FIELD_DOMAIN_TYPE", self.source)

    def test_only_three_non_authorizing_transfer_actions_exist(self) -> None:
        for action in ("--stage-manifest", "--export-rendezvous", "--stage-envelope"):
            self.assertIn(action, self.source)
        self.assertIn("FIELD_AUTHORIZATION_MANIFEST_STAGED_NON_AUTHORIZING", self.source)
        self.assertIn("FIELD_AUTHORIZATION_RENDEZVOUS_EXPORTED_NON_AUTHORIZING", self.source)
        self.assertIn("FIELD_AUTHORIZATION_ENVELOPE_STAGED_NOT_AUTHORITY_NOT_PHYSICAL_GO", self.source)

    def test_direction_and_subject_order_are_explicit(self) -> None:
        self.assertIn('copy_to_container "$staged" "$MANIFEST_REMOTE"', self.source)
        self.assertIn('copy_from_container "$RENDEZVOUS_REMOTE" "$staged"', self.source)
        self.assertIn('copy_to_container "$staged" "$ENVELOPE_REMOTE"', self.source)
        self.assertLess(self.source.index('copy_from_container "$RENDEZVOUS_REMOTE" "$staged"'), self.source.index('publish_fresh_local_file "$staged" "$NEMBRA_SIGNER_RENDEZVOUS_OUTPUT"'))

    def test_device_and_local_subjects_do_not_travel_on_positional_argv(self) -> None:
        self.assertIn("NEMBRA_FIELD_DEVICE_ID", self.source)
        self.assertIn("NEMBRA_RETAINED_INSTALL_MANIFEST_PATH", self.source)
        self.assertIn("NEMBRA_SIGNER_RENDEZVOUS_OUTPUT", self.source)
        self.assertIn("NEMBRA_FIELD_AUTHORIZATION_ENVELOPE_PATH", self.source)
        self.assertIn('[[ "$#" == 1 ]]', self.source)

    def test_local_custody_is_fail_closed(self) -> None:
        for token in ("O_NOFOLLOW", "O_EXCL", "st_nlink != 1", "st_uid != os.geteuid()", "0o022", "os.fsync"):
            self.assertIn(token, self.source)
        self.assertIn("os.O_DIRECTORY | no_follow", self.source)

    def test_transport_has_no_install_launch_or_scooter_write_primitive(self) -> None:
        forbidden = (
            "devicectl device install",
            "devicectl device process launch",
            "writeValue(",
            "publishDps",
            "resetFactory",
            "removeDevice",
            "unbind",
            "firmwareUpgrade",
        )
        for token in forbidden:
            self.assertNotIn(token, self.source)


if __name__ == "__main__":
    unittest.main()
