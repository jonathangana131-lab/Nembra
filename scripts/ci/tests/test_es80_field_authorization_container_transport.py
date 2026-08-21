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

    def test_transport_byte_bounds_match_package_contracts(self) -> None:
        self.assertIn("MANIFEST_MAX_BYTES=16384", self.source)
        self.assertIn("RENDEZVOUS_MAX_BYTES=4096", self.source)
        self.assertIn("ENVELOPE_MAX_BYTES=32768", self.source)
        self.assertNotIn("ENVELOPE_MAX_BYTES=1048576", self.source)

    def test_only_three_non_authorizing_transfer_actions_exist(self) -> None:
        for action in ("--stage-manifest", "--export-rendezvous", "--stage-envelope"):
            self.assertIn(action, self.source)
        self.assertIn("FIELD_AUTHORIZATION_MANIFEST_STAGED_NON_AUTHORIZING", self.source)
        self.assertIn("FIELD_AUTHORIZATION_RENDEZVOUS_EXPORTED_NON_AUTHORIZING", self.source)
        self.assertIn("FIELD_AUTHORIZATION_ENVELOPE_STAGED_NOT_AUTHORITY_NOT_PHYSICAL_GO", self.source)

    def test_direction_and_subject_order_are_explicit(self) -> None:
        self.assertIn('copy_to_container "$manifest_binding_snapshot" "$MANIFEST_REMOTE"', self.source)
        self.assertIn('copy_from_container "$RENDEZVOUS_REMOTE" "$staged"', self.source)
        self.assertIn('copy_to_container "$staged" "$ENVELOPE_REMOTE"', self.source)
        self.assertLess(
            self.source.index('copy_from_container "$RENDEZVOUS_REMOTE" "$staged"'),
            self.source.index(
                'publish_fresh_local_file "$staged" "$NEMBRA_SIGNER_RENDEZVOUS_OUTPUT"'
            ),
        )

    def test_device_and_local_subjects_do_not_travel_on_positional_argv(self) -> None:
        self.assertIn("NEMBRA_FIELD_DEVICE_ID", self.source)
        self.assertIn("NEMBRA_RETAINED_INSTALL_MANIFEST_PATH", self.source)
        self.assertIn("NEMBRA_SIGNER_RENDEZVOUS_OUTPUT", self.source)
        self.assertIn("NEMBRA_FIELD_AUTHORIZATION_ENVELOPE_PATH", self.source)
        self.assertIn('[[ "$#" == 1 ]]', self.source)

    def test_selected_device_is_cross_bound_to_retained_manifest_before_device_contact(self) -> None:
        for token in (
            '[[ "$NEMBRA_FIELD_DEVICE_ID" =~ ^([0-9A-Fa-f]{40}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16})$ ]]',
            'manifest_binding_snapshot="$SCRATCH/retained-install-manifest.binding.json"',
            'verify_manifest_device_binding "$manifest_binding_snapshot"',
            "intendedDevicePseudonymSHA256",
            "hashlib.sha256(device_id.encode('utf-8')).hexdigest()",
            "hmac.compare_digest(observed, expected)",
            "object_pairs_hook=reject_duplicates",
            "json.dumps(manifest, ensure_ascii=False, separators=(',', ':'), sort_keys=True)",
        ):
            self.assertIn(token, self.source)
        self.assertNotIn("indent=2", self.source)
        self.assertNotIn(".encode('utf-8') + b'\\n'", self.source)
        self.assertLess(
            self.source.index('verify_manifest_device_binding "$manifest_binding_snapshot"'),
            self.source.index('case "$ACTION" in', self.source.index('verify_manifest_device_binding()')),
        )
        self.assertIn(
            ': "${NEMBRA_RETAINED_INSTALL_MANIFEST_PATH:?Set NEMBRA_RETAINED_INSTALL_MANIFEST_PATH to the exact retained-install manifest for this attempt.}"',
            self.source,
        )

    def test_local_custody_is_fail_closed(self) -> None:
        for token in (
            "O_NOFOLLOW",
            "O_EXCL",
            "st_nlink != 1",
            "st_uid != os.geteuid()",
            "0o022",
            "os.fsync",
        ):
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
        self.assertIn(
            '[[ "$TRANSPORT_WORKTREE_BLOB" == "$TRANSPORT_TRACKED_BLOB" ]]',
            self.source,
        )
        self.assertIn(
            '[[ "$CONTRACT_WORKTREE_BLOB" == "$CONTRACT_TRACKED_BLOB" ]]',
            self.source,
        )
        self.assertIn(
            '[[ "$CONTRACT_MATERIALIZED_BLOB" == "$CONTRACT_TRACKED_BLOB" ]]',
            self.source,
        )
        self.assertNotIn(
            '/bin/bash -p "$ROOT/scripts/ci/xcode27_devicectl_manifest_transport_contract.sh"',
            self.source,
        )

    def test_git_provenance_rejects_caller_repository_and_config_steering(self) -> None:
        for token in (
            "GIT_DIR",
            "GIT_WORK_TREE",
            "GIT_COMMON_DIR",
            "GIT_OBJECT_DIRECTORY",
            "GIT_ALTERNATE_OBJECT_DIRECTORIES",
            "GIT_INDEX_FILE",
            "GIT_REPLACE_REF_BASE",
            "GIT_CONFIG_COUNT",
            "GIT_CONFIG_PARAMETERS",
            "GIT_CONFIG_KEY_*",
            "GIT_CONFIG_VALUE_*",
            "GIT_NO_REPLACE_OBJECTS=1",
            "GIT_CONFIG_NOSYSTEM=1",
            "GIT_CONFIG_GLOBAL=/dev/null",
        ):
            self.assertIn(token, self.source)
        guard = self.source.index("for inherited_git_name in")
        first_git_read = self.source.index("rev-parse --verify 'HEAD^{commit}'")
        self.assertLess(guard, first_git_read)

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
