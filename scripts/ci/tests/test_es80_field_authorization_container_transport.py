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
            'retained-install-manifest.incoming',
            'retained-install-manifest.commit',
            'signer-rendezvous.json',
            'authorization-envelope.incoming',
            'authorization-envelope.commit',
            'xcode27_devicectl_manifest_transport_contract.sh',
        ):
            self.assertIn(token, self.source)
        self.assertNotIn("NEMBRA_FIELD_BUNDLE_ID", self.source)
        self.assertNotIn("NEMBRA_FIELD_DOMAIN_TYPE", self.source)
        self.assertNotIn('MANIFEST_REMOTE="$FIELD_DIRECTORY/retained-install-manifest.json"', self.source)
        self.assertNotIn('ENVELOPE_REMOTE="$FIELD_DIRECTORY/authorization-envelope.json"', self.source)

    def test_transport_byte_bounds_match_package_contracts(self) -> None:
        self.assertIn("MANIFEST_MAX_BYTES=16384", self.source)
        self.assertIn("RENDEZVOUS_MAX_BYTES=4096", self.source)
        self.assertIn("ENVELOPE_MAX_BYTES=32768", self.source)
        self.assertIn("COMMIT_RECORD_BYTES=65", self.source)
        self.assertNotIn("ENVELOPE_MAX_BYTES=1048576", self.source)

    def test_only_three_non_authorizing_transfer_actions_exist(self) -> None:
        for action in ("--stage-manifest", "--export-rendezvous", "--stage-envelope"):
            self.assertIn(action, self.source)
        self.assertIn("FIELD_AUTHORIZATION_MANIFEST_STAGED_NON_AUTHORIZING", self.source)
        self.assertIn("FIELD_AUTHORIZATION_RENDEZVOUS_EXPORTED_NON_AUTHORIZING", self.source)
        self.assertIn("FIELD_AUTHORIZATION_ENVELOPE_STAGED_NOT_AUTHORITY_NOT_PHYSICAL_GO", self.source)

    def test_poll_safe_subject_order_is_incoming_then_digest_commit(self) -> None:
        manifest_incoming = 'copy_to_container "$staged" "$MANIFEST_INCOMING_REMOTE"'
        manifest_commit = 'copy_to_container "$commit" "$MANIFEST_COMMIT_REMOTE"'
        envelope_incoming = 'copy_to_container "$staged" "$ENVELOPE_INCOMING_REMOTE"'
        envelope_commit = 'copy_to_container "$commit" "$ENVELOPE_COMMIT_REMOTE"'
        for token in (manifest_incoming, manifest_commit, envelope_incoming, envelope_commit):
            self.assertIn(token, self.source)
        self.assertLess(self.source.index(manifest_incoming), self.source.index(manifest_commit))
        self.assertLess(self.source.index(envelope_incoming), self.source.index(envelope_commit))
        self.assertIn('copy_from_container "$RENDEZVOUS_REMOTE" "$staged"', self.source)
        self.assertLess(
            self.source.index('copy_from_container "$RENDEZVOUS_REMOTE" "$staged"'),
            self.source.index('publish_fresh_local_file "$staged" "$NEMBRA_SIGNER_RENDEZVOUS_OUTPUT"'),
        )

    def test_completion_record_is_exact_sha256_plus_lf_under_isolated_descriptor_custody(self) -> None:
        for token in (
            "make_commit_record()",
            '/usr/bin/python3 -I -B - "$source" "$destination"',
            "import hashlib, os, stat, sys",
            "os.O_RDONLY | no_follow",
            "hashlib.sha256()",
            "identity(before) != identity(after)",
            "digest.hexdigest().encode('ascii') + b'\\n'",
            "os.O_WRONLY | os.O_CREAT | os.O_EXCL | no_follow",
            "os.fsync(out)",
            'make_commit_record "$staged" "$commit"',
        ):
            self.assertIn(token, self.source)
        self.assertNotIn("/usr/bin/shasum -a 256", self.source)
        self.assertNotIn("/usr/bin/awk", self.source)

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

    def test_transport_and_help_contract_are_bound_to_exact_tracked_bytes(self) -> None:
        for token in (
            'TRANSPORT_RELATIVE_PATH="scripts/field/transfer_field_authorization.command"',
            'CONTRACT_RELATIVE_PATH="scripts/ci/xcode27_devicectl_manifest_transport_contract.sh"',
            "rev-parse --verify 'HEAD^{commit}'",
            'TRANSPORT_TRACKED_BLOB=',
            'CONTRACT_TRACKED_BLOB=',
            'TRANSPORT_WORKTREE_BLOB=',
            'CONTRACT_WORKTREE_BLOB=',
            'CONTRACT_MATERIALIZED_BLOB=',
            'git -C "$ROOT" show "${REPOSITORY_HEAD}:${CONTRACT_RELATIVE_PATH}"',
            'ARTIFACTS_DIR="$SCRATCH/devicectl-help" /bin/bash -p "$CONTRACT_EXEC"',
        ):
            self.assertIn(token, self.source)
        self.assertIn('[[ "$TRANSPORT_WORKTREE_BLOB" == "$TRANSPORT_TRACKED_BLOB" ]]', self.source)
        self.assertIn('[[ "$CONTRACT_WORKTREE_BLOB" == "$CONTRACT_TRACKED_BLOB" ]]', self.source)
        self.assertIn('[[ "$CONTRACT_MATERIALIZED_BLOB" == "$CONTRACT_TRACKED_BLOB" ]]', self.source)
        self.assertNotIn('/bin/bash -p "$ROOT/scripts/ci/xcode27_devicectl_manifest_transport_contract.sh"', self.source)

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
