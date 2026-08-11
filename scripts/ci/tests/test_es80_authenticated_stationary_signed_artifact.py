#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import io
import os
import plistlib
import stat
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_signed_artifact.py"
SPEC = importlib.util.spec_from_file_location("signed_artifact", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load retained signed-artifact module")
signed = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(signed)

SOURCE = "a" * 40
DEPENDENCY = "b" * 64
DEVICE = "00008101-0012345678901234"
TEAM = "ABCDE12345"


class SignedArtifactTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        (self.repo / "Podfile.lock").write_bytes(b"private-lock")
        self.dependency = signed._sha_file(self.repo / "Podfile.lock")
        self.device = self.root / "device.udid"
        self.device.write_text(DEVICE + "\n", encoding="utf-8")
        os.chmod(self.device, 0o600)
        self.app = (
            self.root
            / "tmp"
            / "NembraAuthenticatedCaptureDerived"
            / "Build"
            / "Products"
            / "Debug-iphoneos"
            / signed.APP_NAME
        )
        self.app.mkdir(parents=True)
        self.profile_payload = {
            "ProvisionedDevices": [DEVICE],
            "TeamIdentifier": [TEAM],
            "Entitlements": {
                "application-identifier": f"{TEAM}.{signed.BUNDLE}",
                "com.apple.developer.team-identifier": TEAM,
                "com.apple.developer.applesignin": ["Default"],
            },
        }
        self.write_app()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_app(self, **overrides: object) -> None:
        info = {
            "CFBundleIdentifier": signed.BUNDLE,
            "NembraCaptureBuildIdentifier": f"capture-v14-{SOURCE[:12]}",
            "NembraCaptureSourceCommitSHA": SOURCE,
            "NembraCaptureTuyaDependencyLockSHA256": self.dependency,
            "NembraCaptureProcedureIdentifier": signed.PROC,
        }
        info.update(overrides)
        (self.app / "Info.plist").write_bytes(plistlib.dumps(info))
        (self.app / "embedded.mobileprovision").write_bytes(b"signed-profile")
        (self.app / "Nembra Capture").write_bytes(b"mach-o-placeholder")
        os.chmod(self.app / "Nembra Capture", 0o755)

    def runner(self, command: list[str]) -> subprocess.CompletedProcess[bytes]:
        if command[:3] == ["/usr/bin/codesign", "--verify", "--strict"]:
            return subprocess.CompletedProcess(command, 0, b"", b"")
        if command[:3] == ["/usr/bin/codesign", "-d", "--verbose=4"]:
            return subprocess.CompletedProcess(
                command,
                0,
                b"",
                f"Identifier={signed.BUNDLE}\nTeamIdentifier={TEAM}\n".encode(),
            )
        if command[:3] == ["/usr/bin/codesign", "-d", "--entitlements"]:
            return subprocess.CompletedProcess(command, 0, plistlib.dumps(self.profile_payload["Entitlements"]), b"")
        if command[:4] == ["/usr/bin/security", "cms", "-D", "-i"]:
            return subprocess.CompletedProcess(
                command, 0, plistlib.dumps(self.profile_payload), b""
            )
        raise AssertionError(f"unexpected trusted tool command: {command}")

    def install_subject(self) -> dict[str, object]:
        return {
            "sourceCommitSHA": SOURCE,
            "bundleIdentifier": signed.BUNDLE,
        }

    def test_end_to_end_retains_and_reinspects_exact_signed_ipa(self) -> None:
        output = self.root / signed.IPA_NAME
        with mock.patch.dict(os.environ, {"TMPDIR": str(self.root / "tmp")}, clear=False):
            result = signed.retain_and_reinspect(
                self.repo,
                SOURCE,
                self.device,
                self.install_subject(),
                output,
                runner=self.runner,
            )
        self.assertTrue(output.is_file())
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
        self.assertEqual(result["authority"], "nembra-authenticated-stationary-retained-signed-artifact-v1")
        self.assertEqual(result["sourceCommitSHA"], SOURCE)
        self.assertEqual(result["tuyaDependencyLockSHA256"], self.dependency)
        self.assertEqual(result["retainedIPASHA256"], signed._sha_file(output))
        self.assertTrue(result["codesignVerified"])
        self.assertTrue(result["intendedDeviceIncluded"])
        self.assertFalse(result["physicalAuthorityCreated"])
        with zipfile.ZipFile(output) as archive:
            self.assertIn(f"Payload/{signed.APP_NAME}/Info.plist", archive.namelist())

    def test_published_ipa_can_be_independently_reinspected(self) -> None:
        output=self.root / signed.IPA_NAME
        with mock.patch.dict(os.environ,{"TMPDIR":str(self.root / "tmp")},clear=False):
            first=signed.retain_and_reinspect(self.repo,SOURCE,self.device,self.install_subject(),output,runner=self.runner)
        second=signed.reinspect_retained(output,self.repo,SOURCE,self.device,self.install_subject(),runner=self.runner)
        self.assertEqual(first,second)

    def test_output_is_no_replace_and_canonical_filename_only(self) -> None:
        output = self.root / signed.IPA_NAME
        output.write_bytes(b"existing")
        os.chmod(output, 0o600)
        with mock.patch.dict(os.environ, {"TMPDIR": str(self.root / "tmp")}, clear=False):
            with self.assertRaises(signed.SignedArtifactError):
                signed.retain_and_reinspect(
                    self.repo, SOURCE, self.device, self.install_subject(), output, runner=self.runner
                )
        self.assertEqual(output.read_bytes(), b"existing")
        with mock.patch.dict(os.environ, {"TMPDIR": str(self.root / "tmp")}, clear=False):
            with self.assertRaises(signed.SignedArtifactError):
                signed.retain_and_reinspect(
                    self.repo,
                    SOURCE,
                    self.device,
                    self.install_subject(),
                    self.root / "wrong.ipa",
                    runner=self.runner,
                )

    def test_wrong_source_build_procedure_bundle_or_dependency_is_rejected(self) -> None:
        for key, value in (
            ("NembraCaptureSourceCommitSHA", "c" * 40),
            ("NembraCaptureBuildIdentifier", "capture-v14-wrong"),
            ("NembraCaptureProcedureIdentifier", "ES80-FINGERPRINT-v1"),
            ("CFBundleIdentifier", "com.example.fake"),
            ("NembraCaptureTuyaDependencyLockSHA256", "d" * 64),
        ):
            with self.subTest(key=key):
                self.write_app(**{key: value})
                with self.assertRaises(signed.SignedArtifactError):
                    signed._app_evidence(
                        self.app,
                        source=SOURCE,
                        dependency_sha=self.dependency,
                        intended_device=DEVICE,
                        runner=self.runner,
                    )
                self.write_app()

    def test_effective_signed_entitlements_are_independently_required(self) -> None:
        def missing_apple(command: list[str]) -> subprocess.CompletedProcess[bytes]:
            if command[:3] == ["/usr/bin/codesign", "-d", "--entitlements"]:
                entitlements = dict(self.profile_payload["Entitlements"]); entitlements.pop("com.apple.developer.applesignin", None)
                return subprocess.CompletedProcess(command, 0, plistlib.dumps(entitlements), b"")
            return self.runner(command)
        with self.assertRaises(signed.SignedArtifactError):
            signed._app_evidence(self.app, source=SOURCE, dependency_sha=self.dependency, intended_device=DEVICE, runner=missing_apple)

    def test_profile_wrong_team_application_or_missing_device_is_rejected(self) -> None:
        original = self.profile_payload
        cases = [
            {**original, "ProvisionedDevices": ["other-device"]},
            {**original, "TeamIdentifier": ["OTHER12345"]},
            {
                **original,
                "Entitlements": {
                    **original["Entitlements"],
                    "application-identifier": f"{TEAM}.com.example.fake",
                },
            },
        ]
        for payload in cases:
            with self.subTest(payload=payload):
                self.profile_payload = payload
                with self.assertRaises(signed.SignedArtifactError):
                    signed._app_evidence(
                        self.app,
                        source=SOURCE,
                        dependency_sha=self.dependency,
                        intended_device=DEVICE,
                        runner=self.runner,
                    )
        self.profile_payload = original

    def test_codesign_wrong_identifier_or_team_is_rejected(self) -> None:
        def wrong_identifier(command: list[str]) -> subprocess.CompletedProcess[bytes]:
            if command[:3] == ["/usr/bin/codesign", "--verify", "--strict"]:
                return subprocess.CompletedProcess(command, 0, b"", b"")
            if command[:3] == ["/usr/bin/codesign", "-d", "--verbose=4"]:
                return subprocess.CompletedProcess(command, 0, b"", b"Identifier=com.example.fake\nTeamIdentifier=ABCDE12345\n")
            return self.runner(command)

        with self.assertRaises(signed.SignedArtifactError):
            signed._app_evidence(
                self.app,
                source=SOURCE,
                dependency_sha=self.dependency,
                intended_device=DEVICE,
                runner=wrong_identifier,
            )

    def test_zip_duplicate_traversal_symlink_and_expansion_limit_are_rejected(self) -> None:
        def archive(entries: list[tuple[zipfile.ZipInfo, bytes]]) -> Path:
            path = self.root / f"case-{len(list(self.root.glob('case-*.ipa')))}.ipa"
            with zipfile.ZipFile(path, "w") as z:
                for info, payload in entries:
                    z.writestr(info, payload)
            return path

        regular = zipfile.ZipInfo(f"Payload/{signed.APP_NAME}/Info.plist")
        regular.create_system = 3
        regular.external_attr = (stat.S_IFREG | 0o600) << 16
        duplicate = archive([(regular, b"a"), (regular, b"b")])
        with self.assertRaises(signed.SignedArtifactError):
            signed._safe_zip_members(duplicate)

        traversal = zipfile.ZipInfo("Payload/../escape")
        traversal.create_system = 3
        traversal.external_attr = (stat.S_IFREG | 0o600) << 16
        with self.assertRaises(signed.SignedArtifactError):
            signed._safe_zip_members(archive([(traversal, b"x")]))

        symlink = zipfile.ZipInfo(f"Payload/{signed.APP_NAME}/link")
        symlink.create_system = 3
        symlink.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaises(signed.SignedArtifactError):
            signed._safe_zip_members(archive([(symlink, b"target")]))

        with mock.patch.object(signed, "MAX_ARCHIVE_BYTES", 2):
            with self.assertRaises(signed.SignedArtifactError):
                signed._safe_zip_members(archive([(regular, b"abc")]))

    def test_signed_app_symlink_hardlink_and_private_device_custody_are_rejected(self) -> None:
        link = self.app / "bad-link"
        link.symlink_to("Info.plist")
        with self.assertRaises(signed.SignedArtifactError):
            signed._tree_manifest(self.app)
        link.unlink()

        hard = self.app / "hard-copy"
        os.link(self.app / "Info.plist", hard)
        with self.assertRaises(signed.SignedArtifactError):
            signed._tree_manifest(self.app)
        hard.unlink()

        os.chmod(self.device, 0o644)
        with self.assertRaises(signed.SignedArtifactError):
            signed._read_intended_device(self.device, self.repo)
        os.chmod(self.device, 0o600)
        inside = self.repo / "device.udid"
        inside.write_text(DEVICE, encoding="utf-8")
        os.chmod(inside, 0o600)
        with self.assertRaises(signed.SignedArtifactError):
            signed._read_intended_device(inside, self.repo)

    def test_pre_and_post_retained_tree_mismatch_is_rejected(self) -> None:
        original = signed._app_evidence
        calls = 0

        def drifting(*args: object, **kwargs: object) -> dict[str, object]:
            nonlocal calls
            result = dict(original(*args, **kwargs))
            calls += 1
            if calls == 2:
                result["treeSHA256"] = "0" * 64
            return result

        output = self.root / signed.IPA_NAME
        with mock.patch.dict(os.environ, {"TMPDIR": str(self.root / "tmp")}, clear=False), mock.patch.object(
            signed, "_app_evidence", side_effect=drifting
        ):
            with self.assertRaises(signed.SignedArtifactError):
                signed.retain_and_reinspect(
                    self.repo, SOURCE, self.device, self.install_subject(), output, runner=self.runner
                )
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
