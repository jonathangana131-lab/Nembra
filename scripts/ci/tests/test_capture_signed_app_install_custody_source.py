#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
FIELD_GATE = REPOSITORY / ".github/workflows/capture-field-build-provenance.yml"
HELPER = "scripts/ci/es80_signed_app_install_guard.py"
UNIT_TEST = "scripts/ci/tests/test_es80_signed_app_install_guard.py"
SOURCE_TEST = "scripts/ci/tests/test_capture_signed_app_install_custody_source.py"


class SignedAppInstallCustodySourceTests(unittest.TestCase):
    def test_exact_subject_is_frozen_after_authority_checks_and_before_install(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        xcode_open = 'open -a Xcode "$ROOT/NembraCapture.xcworkspace" >/dev/null 2>&1 || true'
        strict_signature = '/usr/bin/codesign --verify --deep --strict "$APP"'
        profile_acceptance = 'say "Final signed app and embedded provisioning profile authorize Sign in with Apple for one exact App ID and the selected team"'
        helper_binding = 'SIGNED_APP_INSTALL_GUARD="$ROOT/scripts/ci/es80_signed_app_install_guard.py"'
        frozen_digest = 'SIGNED_APP_SUBJECT_SHA256="$(/usr/bin/python3 -I "$SIGNED_APP_INSTALL_GUARD" digest --app "$APP")"'
        install_start = 'say "Installing SDK-integrated Capture on the intended iPhone"'
        guard_call = '/usr/bin/python3 -I "$SIGNED_APP_INSTALL_GUARD" guard'

        for marker in (xcode_open, strict_signature, profile_acceptance, helper_binding, frozen_digest, install_start, guard_call):
            self.assertIn(marker, source, marker)

        self.assertLess(source.index(xcode_open), source.index(strict_signature))
        self.assertLess(source.index(strict_signature), source.index(profile_acceptance))
        self.assertLess(source.index(profile_acceptance), source.index(frozen_digest))
        self.assertLess(source.index(frozen_digest), source.index(install_start))
        self.assertLess(source.index(install_start), source.index(guard_call))

        self.assertEqual(source.count(xcode_open), 1, "Xcode activation must not reopen a mutation seam after the signed subject is frozen")
        self.assertNotIn('if xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP"', source)
        self.assertIn('/usr/bin/xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP"', source)
        self.assertIn('[[ "$INSTALL_RESULT" == "74" || "$INSTALL_RESULT" == "75" ]]', source)
        self.assertIn('Signed Capture app install custody failed', source)

    def test_canonical_field_gate_owns_helper_tests_and_installer_contract(self) -> None:
        workflow = FIELD_GATE.read_text(encoding="utf-8")
        for path in (HELPER, UNIT_TEST, SOURCE_TEST):
            self.assertIn(f"      - {path}", workflow)
        self.assertIn("python3 -m py_compile scripts/ci/es80_signed_app_install_guard.py", workflow)
        self.assertIn("python3 -I scripts/ci/tests/test_es80_signed_app_install_guard.py", workflow)
        self.assertIn("python3 -I scripts/ci/tests/test_capture_signed_app_install_custody_source.py", workflow)


if __name__ == "__main__":
    unittest.main(verbosity=2)
