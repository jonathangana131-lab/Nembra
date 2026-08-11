#!/usr/bin/env python3
"""Expected-red: protected signed-app custody must originate from the build-produced bundle.

The current field installer starts signed-app custody only after xcodebuild has returned. It
fingerprints the user-writable DerivedData app and then snapshots that current pathname into a
root-owned stage. This diagnostic uses the real custody fingerprint helper to demonstrate the
missing origin binding: a same-UID actor can replace the DerivedData app after the build boundary
but before the first fingerprint; the protected stage then faithfully authenticates the
replacement against a self-derived fingerprint, while the original build output can be restored.

This test does not claim that a toy fixture satisfies Apple's signing/profile checks. Those later
checks authenticate properties of the already-promoted staged subject; they do not establish that
subject's compiler origin. The invariant under test is narrower: bytes promoted as the signed field
artifact must be mechanically bound to the bundle produced by the accepted xcodebuild invocation.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import os
import shutil
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
INSTALLER = REPOSITORY / "scripts/field/install_one_time_capture.command"
HELPER = REPOSITORY / "scripts/ci/capture_signed_app_install_custody.py"


def load_helper():
    spec = importlib.util.spec_from_file_location("capture_signed_app_install_custody", HELPER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load signed-app custody helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureSignedAppPreStageOriginTests(unittest.TestCase):
    def test_post_build_replacement_cannot_become_promoted_install_subject(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        build_marker = 'build || die "Private inputs changed while xcodebuild was running, vnode custody failed, or the signed build itself failed. No field artifact was admitted."'
        app_marker = 'APP="$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app"'
        fingerprint_marker = 'SOURCE_APP_TREE_SHA256="$(printf \'%s\' "$SIGNED_APP_CUSTODY_HELPER_BASE64" | /usr/bin/base64 -D | /usr/bin/python3 -I - fingerprint --app "$APP")"'
        stage_marker = 'APP_INSTALL_STAGE_ROOT="$(/usr/bin/sudo /usr/bin/mktemp -d /private/tmp/nembra-authenticated-capture-install.XXXXXX)"'
        copy_marker = '/usr/bin/sudo /usr/bin/ditto --noacl "$APP" "$APP_INSTALL_STAGE"'
        switch_marker = 'APP="$APP_INSTALL_STAGE"'

        build_index = source.find(build_marker)
        app_index = source.find(app_marker, build_index + 1)
        fingerprint_index = source.find(fingerprint_marker, app_index + 1)
        stage_index = source.find(stage_marker, fingerprint_index + 1)
        copy_index = source.find(copy_marker, stage_index + 1)
        switch_index = source.find(switch_marker, copy_index + 1)

        self.assertGreaterEqual(build_index, 0, "diagnostic lost the accepted xcodebuild completion boundary")
        self.assertGreater(app_index, build_index, "DerivedData app selection must remain after xcodebuild")
        self.assertGreater(fingerprint_index, app_index, "diagnostic lost the first post-build app fingerprint")
        self.assertGreater(stage_index, fingerprint_index, "current protected stage must remain downstream of source fingerprint")
        self.assertGreater(copy_index, stage_index, "diagnostic lost the protected-stage snapshot")
        self.assertGreater(switch_index, copy_index, "diagnostic lost the protected-stage authority switch")

        helper = load_helper()
        with tempfile.TemporaryDirectory(prefix="nembra-signed-app-prestage-origin-") as temporary:
            root = Path(temporary)
            products = root / "Derived/Build/Products/Debug-iphoneos"
            products.mkdir(parents=True)
            app = products / "Nembra Capture.app"
            app.mkdir()
            (app / "Info.plist").write_text("accepted build provenance\n", encoding="utf-8")
            (app / "Nembra Capture").write_bytes(b"ACCEPTED_XCODEBUILD_OUTPUT\n")

            # This is the authority value the installer would need to retain from the actual
            # build-produced subject in order to distinguish it from a later replacement. Current
            # production intentionally does not compute/retain this value at the build boundary.
            build_output_fingerprint = helper.fingerprint(app)

            substitute = root / "substitute.app"
            substitute.mkdir()
            # Give the replacement the same superficial provenance shape while changing executable
            # bytes. Later signing/provisioning checks reason about the staged subject; they do not
            # recover which directory xcodebuild originally produced.
            (substitute / "Info.plist").write_text("accepted build provenance\n", encoding="utf-8")
            (substitute / "Nembra Capture").write_bytes(b"SUBSTITUTED_AFTER_XCODEBUILD\n")

            preserved_build_output = root / "accepted-output.app"
            os.rename(app, preserved_build_output)
            os.rename(substitute, app)

            # Exact current custody algorithm starts here: fingerprint whatever now occupies the
            # mutable DerivedData pathname, then copy and authenticate the stage against that same
            # self-derived value.
            promoted_source_fingerprint = helper.fingerprint(app)
            protected_stage = root / "protected/Nembra Capture.app"
            protected_stage.parent.mkdir()
            shutil.copytree(app, protected_stage, symlinks=True)
            staged_fingerprint = helper.fingerprint(protected_stage)
            self.assertEqual(
                staged_fingerprint,
                promoted_source_fingerprint,
                "fixture must prove the current source->stage fingerprint equality accepts the replacement",
            )

            # A same-UID actor can restore the original DerivedData pathname after the promotion;
            # endpoint inspection of that pathname cannot retroactively establish stage origin.
            promoted_copy = root / "promoted-substitute.app"
            os.rename(app, promoted_copy)
            os.rename(preserved_build_output, app)
            self.assertEqual(helper.fingerprint(app), build_output_fingerprint)
            self.assertNotEqual(staged_fingerprint, build_output_fingerprint)

            self.assertEqual(
                staged_fingerprint,
                build_output_fingerprint,
                "protected signed-app stage was authenticated against a fingerprint first derived only after the mutable post-build replacement window; bind the xcodebuild-produced bundle through the compiler-output -> protected-stage handoff instead of self-authorizing whichever bundle occupies DerivedData at fingerprint time",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
