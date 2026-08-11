#!/usr/bin/env python3
"""Expected-red: signed-app authority must remain bound from verification through install."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
GUARD_PATH = REPOSITORY / "scripts/ci/es80_signed_app_install_guard.py"


def load_guard():
    name = "nembra_signed_app_verification_gap_guard"
    spec = importlib.util.spec_from_file_location(name, GUARD_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load signed-app install guard")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class QuietBackend:
    def register(self, descriptor: int) -> None:
        del descriptor

    def events(self, timeout: float):
        del timeout
        return ()

    def close(self) -> None:
        pass


class FinishedProcess:
    returncode = 0

    def poll(self):
        return 0

    def terminate(self) -> None:
        pass

    def wait(self, timeout=None):
        del timeout
        return 0

    def kill(self) -> None:
        pass


class SignedAppVerificationCustodyGapTests(unittest.TestCase):
    def test_post_verification_swap_cannot_be_promoted_to_expected_install_subject(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        strict_signature = '/usr/bin/codesign --verify --deep --strict "$APP"'
        profile_acceptance = (
            'say "Final signed app and embedded provisioning profile authorize Sign in with Apple '
            'for one exact App ID and the selected team"'
        )
        digest_freeze = (
            'SIGNED_APP_SUBJECT_SHA256="$(/usr/bin/python3 -I "$SIGNED_APP_INSTALL_GUARD" '
            'digest --app "$APP")"'
        )
        guard_call = '/usr/bin/python3 -I "$SIGNED_APP_INSTALL_GUARD" guard'
        for marker in (strict_signature, profile_acceptance, digest_freeze, guard_call):
            self.assertIn(marker, source)
        self.assertLess(source.index(strict_signature), source.index(profile_acceptance))
        self.assertLess(
            source.index(profile_acceptance),
            source.index(digest_freeze),
            "diagnostic targets the current unguarded verification-to-digest handoff",
        )
        self.assertLess(source.index(digest_freeze), source.index(guard_call))

        guard = load_guard()
        with tempfile.TemporaryDirectory(prefix="nembra-signed-app-verification-gap-") as temporary:
            app = Path(temporary) / "Nembra Capture.app"
            app.mkdir()
            payload = app / "subject.txt"
            payload.write_text("ACCEPTED_VERIFIED_SUBJECT\n", encoding="utf-8")

            # This digest stands in for the exact filesystem generation on which the
            # installer has just earned signature/provenance/entitlement/profile authority.
            verified_subject = guard.digest_app(app)

            # Same-UID substitution lands after the last authority read but before the
            # current installer computes SIGNED_APP_SUBJECT_SHA256.
            payload.write_text("SUBSTITUTED_AFTER_VERIFICATION\n", encoding="utf-8")
            frozen_after_swap = guard.digest_app(app)
            self.assertNotEqual(verified_subject, frozen_after_swap)

            consumed: list[str] = []

            def popen(_command):
                consumed.append(payload.read_text(encoding="utf-8"))
                return FinishedProcess()

            result = guard.guarded_install(
                app,
                frozen_after_swap,
                ["fake-devicectl"],
                backend_factory=QuietBackend,
                popen_factory=popen,
            )

            self.assertEqual(consumed, ["SUBSTITUTED_AFTER_VERIFICATION\n"])
            self.assertNotEqual(
                result,
                0,
                "the post-verification replacement became the install guard's self-created expected authority; "
                "custody must start before/at authority verification and span through devicectl",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
