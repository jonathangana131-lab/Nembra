#!/usr/bin/env python3
"""Regress the exact build-principal lifetime of the private Tuya read lease."""

from __future__ import annotations

from pathlib import Path
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
ORIGIN = REPOSITORY / "scripts/ci/capture_signed_app_build_origin_custody.py"
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


class CapturePrivateReadLeaseBuildWindowTests(unittest.TestCase):
    def test_orchestrator_admits_only_guarded_private_tuya_inputs(self) -> None:
        source = ORCHESTRATOR.read_text(encoding="utf-8")
        self.assertIn(
            'PRIVATE_READ_RELATIVE_SUBJECTS = (\n'
            '    Path("LocalSecrets/TuyaSDK/ThingSmartCryption.podspec"),\n'
            '    Path("LocalSecrets/TuyaSDK/Build"),\n'
            '    Path("LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec"),\n'
            '    Path("LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"),\n'
            ')',
            source,
        )
        self.assertNotIn('Path("LocalSecrets/TuyaSDK"),', source)
        self.assertNotIn('Path("LocalSecrets/TuyaRuntime"),', source)
        self.assertIn(
            "private_read_lease = _PrivateReadLease(\n"
            "        tuple(repository / relative for relative in PRIVATE_READ_RELATIVE_SUBJECTS),\n"
            "        repository,\n"
            "    )",
            source,
        )
        self.assertIn("private_read_lease=private_read_lease", source)

    def test_lease_is_granted_only_after_build_setup_and_revoked_before_promotion(self) -> None:
        source = ORIGIN.read_text(encoding="utf-8")
        markers = {
            "identity": "_create_local_build_identity(build_name, build_uid, build_gid, home)",
            "attest": "build_groups = _attest_build_identity_groups(",
            "image": "_create_apfs_image(image)",
            "attach": "writable_device = _attach_apfs(image, mountpoint, readonly=False)",
            "command": "guarded_command = _replace_derived_placeholder(command, derived_root)",
            "grant": "grant(build_name)",
            "build": "build = _run_exec_bound_build(",
            "revoke": "private_read_lease.revoke()",
            "lock": "os.chown(mountpoint, 0, 0)",
            "status": "if build.returncode != 0:",
            "readonly": "readonly_device = _attach_apfs(image, mountpoint, readonly=True)",
            "fingerprint": "source_fingerprint = str(fingerprint(source_app))",
        }
        positions = {name: source.find(marker) for name, marker in markers.items()}
        for name, position in positions.items():
            self.assertGreaterEqual(position, 0, f"missing private read-lease build-window marker: {name}")

        self.assertLess(positions["identity"], positions["attest"])
        self.assertLess(positions["attest"], positions["image"])
        self.assertLess(positions["image"], positions["attach"])
        self.assertLess(positions["attach"], positions["command"])
        self.assertLess(positions["command"], positions["grant"])
        self.assertLess(positions["grant"], positions["build"])
        self.assertLess(positions["build"], positions["revoke"])
        self.assertLess(positions["revoke"], positions["lock"])
        self.assertLess(positions["revoke"], positions["status"])
        self.assertLess(positions["revoke"], positions["readonly"])
        self.assertLess(positions["revoke"], positions["fingerprint"])

    def test_failure_cleanup_revokes_before_principal_retirement_and_stage_promotion_fails_closed(self) -> None:
        source = ORIGIN.read_text(encoding="utf-8")
        finally_index = source.index("    finally:\n")
        tail = source[finally_index:]
        revoke_guard = tail.index("if private_read_lease_granted:")
        revoke_call = tail.index("private_read_lease.revoke()", revoke_guard)
        retirement = tail.index("_remove_local_build_identity(build_name, build_uid, require_absent=True)")
        stage_cleanup = tail.index("or lease_error is not None")
        lease_raise = tail.index("if lease_error is not None:\n            raise lease_error")

        self.assertLess(revoke_guard, revoke_call)
        self.assertLess(revoke_call, retirement)
        self.assertLess(stage_cleanup, lease_raise)
        self.assertIn(
            '"private read-lease object does not expose exact grant/revoke lifecycle"',
            source,
        )
        self.assertIn(
            "private read lease did not revoke before build-principal retirement",
            source,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
