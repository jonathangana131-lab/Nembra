#!/usr/bin/env python3
"""Require signed-app verification and install to share one guarded subject.

This is the promoted regression for #2688. The original expected-red fixture proved
that verification of one mutable `.app` pathname followed by a later direct
`devicectl` open could install different bytes. Production closure must instead:
- capture guard + verify/install implementation from exact SOURCE_SHA Git objects;
- execute those implementations from already-open, verified descriptors;
- keep the app tree + parent under vnode/cryptographic custody for the complete
  provenance/signature/profile/install child;
- carry the private device identifier only over stdin for log redaction;
- refuse to launch until guarded installation has returned success.
"""

from __future__ import annotations

from pathlib import Path
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
VERIFY_INSTALL = REPOSITORY / "scripts/field/verify_install_capture_app.command"
GUARD = REPOSITORY / "scripts/ci/capture_signed_app_install_guard.py"


class CaptureSignedAppInstallSubjectTests(unittest.TestCase):
    def test_installer_uses_exact_git_descriptor_bound_guard_and_verifier(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")

        required = (
            'SIGNED_APP_INSTALL_GUARD_RELATIVE_PATH="scripts/ci/capture_signed_app_install_guard.py"',
            'SIGNED_APP_VERIFY_INSTALL_RELATIVE_PATH="scripts/field/verify_install_capture_app.command"',
            '/usr/bin/git show "$SOURCE_SHA:$SIGNED_APP_INSTALL_GUARD_RELATIVE_PATH"',
            '/usr/bin/git show "$SOURCE_SHA:$SIGNED_APP_VERIFY_INSTALL_RELATIVE_PATH"',
            'GUARD_BLOB_SHA="$(/usr/bin/git rev-parse "$SOURCE_SHA:$SIGNED_APP_INSTALL_GUARD_RELATIVE_PATH")"',
            'VERIFY_INSTALL_BLOB_SHA="$(/usr/bin/git rev-parse "$SOURCE_SHA:$SIGNED_APP_VERIFY_INSTALL_RELATIVE_PATH")"',
            'verify_open_git_blob_descriptor 7 "$VERIFY_INSTALL_BLOB_SHA" "$VERIFY_INSTALL_BLOB_BYTES"',
            'verify_open_git_blob_descriptor 8 "$GUARD_BLOB_SHA" "$GUARD_BLOB_BYTES"',
            'exec 7< "$VERIFY_INSTALL_SNAPSHOT"',
            'exec 8< "$GUARD_SNAPSHOT"',
            '/bin/rm -f -- "$GUARD_SNAPSHOT" "$VERIFY_INSTALL_SNAPSHOT"',
            '/usr/bin/python3 -I /dev/fd/8',
            '--pass-fd 7',
            '--app "$APP"',
            '/bin/bash --noprofile --norc -p /dev/fd/7',
        )
        for marker in required:
            self.assertIn(marker, source, marker)

        descriptor_verify = source.index('verify_open_git_blob_descriptor 7')
        unlink = source.index('/bin/rm -f -- "$GUARD_SNAPSHOT" "$VERIFY_INSTALL_SNAPSHOT"')
        guard_start = source.index('/usr/bin/python3 -I /dev/fd/8')
        launch = source.index('say "Launching privately provisioned Capture on the intended iPhone"')
        self.assertLess(descriptor_verify, unlink)
        self.assertLess(unlink, guard_start, "tool pathnames must be gone before authority code executes")
        self.assertLess(guard_start, launch, "physical launch must remain downstream of stable guarded install")

    def test_private_device_identifier_is_stdin_only_at_install_boundary(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        verifier = VERIFY_INSTALL.read_text(encoding="utf-8")
        guarded_call_start = installer.index("# The private intended-device UDID crosses this boundary")
        guarded_call_end = installer.index('say "Launching privately provisioned Capture on the intended iPhone"')
        guarded_call = installer[guarded_call_start:guarded_call_end]

        self.assertIn("builtin printf '%s\\n' \"$DEVICE_UDID\" | /usr/bin/python3 -I /dev/fd/8", guarded_call)
        self.assertNotIn('"$DEVICE_UDID" \\', guarded_call.split('|', 1)[1])
        self.assertNotIn('--device "$DEVICE_UDID"', installer)
        self.assertNotIn('--device "$PRIVATE_DEVICE_UDID"', verifier)
        self.assertIn('--device "$COREDEVICE_ID" "$APP"', verifier)

    def test_authority_checks_and_install_are_inside_same_guarded_child(self) -> None:
        installer = INSTALLER.read_text(encoding="utf-8")
        verifier = VERIFY_INSTALL.read_text(encoding="utf-8")

        self.assertNotIn('devicectl device install app', installer, "main installer must not reopen APP for installation outside the custody child")
        provenance = verifier.index('BUILT_BUILD_IDENTIFIER=')
        signature = verifier.index('/usr/bin/codesign --verify --deep --strict "$APP"')
        entitlements = verifier.index('/usr/bin/codesign -d --entitlements :- --xml "$APP"')
        profile = verifier.index('/usr/bin/security cms -D -i "$BUILT_PROFILE"')
        install = verifier.index('/usr/bin/xcrun devicectl device install app --device "$COREDEVICE_ID" "$APP"')
        self.assertLess(provenance, signature)
        self.assertLess(signature, entitlements)
        self.assertLess(entitlements, profile)
        self.assertLess(profile, install)
        self.assertNotIn('device process launch', verifier, "guarded child must not launch before the parent performs final stable-subject proof")

    def test_guard_custodies_parent_and_every_real_bundle_entry(self) -> None:
        source = GUARD.read_text(encoding="utf-8")
        self.assertIn('paths: set[Path] = {parent, app}', source)
        self.assertIn('for current_raw, directory_names, file_names in os.walk(app, topdown=True, followlinks=False):', source)
        self.assertIn('initial_subject = bundle_subject(app)', source)
        self.assertIn('armed_subject = bundle_subject(app)', source)
        self.assertIn('bundle_subject(app) != initial_subject', source)
        self.assertIn('KQ_NOTE_RENAME', source)
        self.assertIn('KQ_NOTE_WRITE', source)
        self.assertIn('pass_fds=inherited', source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
