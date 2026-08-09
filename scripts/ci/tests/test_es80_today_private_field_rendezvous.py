#!/usr/bin/env python3
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest import mock
import zipfile

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_private_field_rendezvous.py"
spec = importlib.util.spec_from_file_location("private_rendezvous", MODULE_PATH)
rendezvous = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(rendezvous)


class PrivateFieldRendezvousTests(unittest.TestCase):
    UDID = "00008101-001234567890001E"
    NOW = datetime(2026, 8, 9, 6, 0, 0, tzinfo=timezone.utc)

    def candidate(self, *, ipa_sha: str = "a" * 64, ipa_size: int = 123):
        return {
            "sourceCommitSHA": "b" * 40,
            "buildIdentifier": "Capture Build V14-" + "b" * 12,
            "buildInstanceID": "11111111-2222-4333-8444-555555555555",
            "retainedIPASHA256": ipa_sha,
            "retainedIPAByteCount": ipa_size,
            "provisioningProfileSHA256": "c" * 64,
            "provisioningProfileUUID": "PROFILE-UUID",
            "teamIdentifier": "ABCDE12345",
        }

    def write_private_udid(self, root: Path, *, mode: int = 0o600) -> Path:
        path = root / "intended-device"
        path.write_text(self.UDID + "\n", encoding="utf-8")
        path.chmod(mode)
        return path

    def operator_validator(self, path: Path, candidate: dict, now: datetime):
        self.assertEqual(path.name, "operator.json")
        self.assertEqual(now, self.NOW)
        self.assertEqual(candidate["retainedIPASHA256"], "a" * 64)
        return {
            "authority": "operator-field-attestation-not-machine-evidence",
            "recordSHA256": "d" * 64,
            "attestationID": "12345678-1234-4234-8234-123456789abc",
            "recordedAtUTC": "2026-08-09T06:00:00Z",
            "runtimeRendezvousMatched": True,
            "packageResearchAdmissionObserved": True,
            "preflightHealth": "READY",
            "chargerState": "DISCONNECTED",
            "motionState": "STATIONARY",
        }

    def profile_probe(self, **kwargs):
        self.assertEqual(kwargs["intended_device_udid"], self.UDID)
        self.assertEqual(kwargs["now_utc"], self.NOW)
        return {
            "provisioningProfileSHA256": "c" * 64,
            "provisioningProfileUUID": "PROFILE-UUID",
            "provisioningMembershipMode": "explicit-provisioned-device",
            "intendedDeviceMembershipVerified": True,
        }

    def device_probe(self, udid: str):
        self.assertEqual(udid, self.UDID)
        return {
            "connectedDeviceProbeVerified": True,
            "liveDeviceProductType": "iPhone13,2",
            "liveDeviceMarketingName": "iPhone 12",
            "liveDeviceOSVersion": "27.0",
            "liveDeviceDeveloperMode": "enabled",
            "liveDevicePairingState": "paired",
            "liveDeviceTunnelState": "connected",
            "liveDeviceTransport": "wired",
            "installedBundleIdentifier": rendezvous.BUNDLE_ID,
            "installedAppBuiltByDeveloper": True,
            "installedAppURLSHA256": "e" * 64,
            "installedAppBundleVersion": "1",
            "installedAppVersion": "1.0",
            "xcodeVersion": "Xcode 27.0",
            "xcodeBuildVersion": "Build version 18A123",
            "devicectlSHA256": "f" * 64,
        }

    def test_success_binds_private_device_without_publishing_raw_identifier_and_replay_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            private_id = self.write_private_udid(root)
            operator = root / "operator.json"
            operator.write_text("{}", encoding="utf-8")
            state = root / "state"

            subject = rendezvous.verify_private_field_rendezvous(
                candidate_root=root / "candidate",
                candidate=self.candidate(),
                operator_attestation=operator,
                intended_device_udid_file=private_id,
                operator_validator=self.operator_validator,
                now_utc=self.NOW,
                profile_probe=self.profile_probe,
                device_probe=self.device_probe,
                state_dir=state,
            )

            self.assertEqual(subject["authority"], rendezvous.AUTHORITY)
            self.assertTrue(subject["intendedDeviceMembershipVerified"])
            self.assertTrue(subject["connectedDeviceProbeVerified"])
            self.assertEqual(subject["oneTimeObservationConsumption"], "CONSUMED")
            self.assertFalse(subject["rawIntendedDeviceIdentifierPublished"])
            self.assertFalse(subject["physicalResultCollected"])
            rendered = json.dumps(subject, sort_keys=True)
            self.assertNotIn(self.UDID, rendered)
            self.assertEqual(
                subject["deviceCommitmentSHA256"],
                rendezvous._device_commitment(self.UDID),
            )
            markers = list(state.glob("*.json"))
            self.assertEqual(len(markers), 1)
            self.assertEqual(stat.S_IMODE(state.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(markers[0].stat().st_mode), 0o600)

            with self.assertRaisesRegex(
                rendezvous.PrivateFieldRendezvousError,
                "already consumed",
            ):
                rendezvous.verify_private_field_rendezvous(
                    candidate_root=root / "candidate",
                    candidate=self.candidate(),
                    operator_attestation=operator,
                    intended_device_udid_file=private_id,
                    operator_validator=self.operator_validator,
                    now_utc=self.NOW,
                    profile_probe=self.profile_probe,
                    device_probe=self.device_probe,
                    state_dir=state,
                )

    def test_private_identifier_file_must_be_private(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            private_id = self.write_private_udid(root, mode=0o644)
            with self.assertRaisesRegex(
                rendezvous.PrivateFieldRendezvousError,
                "group/other",
            ):
                rendezvous.verify_private_field_rendezvous(
                    candidate_root=root / "candidate",
                    candidate=self.candidate(),
                    operator_attestation=root / "operator.json",
                    intended_device_udid_file=private_id,
                    operator_validator=self.operator_validator,
                    now_utc=self.NOW,
                    profile_probe=self.profile_probe,
                    device_probe=self.device_probe,
                    state_dir=root / "state",
                )

    def test_profile_membership_must_be_verified_before_consumption(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            private_id = self.write_private_udid(root)
            operator = root / "operator.json"
            operator.write_text("{}", encoding="utf-8")
            state = root / "state"

            def rejected_profile(**kwargs):
                return {"intendedDeviceMembershipVerified": False}

            with self.assertRaisesRegex(
                rendezvous.PrivateFieldRendezvousError,
                "membership was not verified",
            ):
                rendezvous.verify_private_field_rendezvous(
                    candidate_root=root / "candidate",
                    candidate=self.candidate(),
                    operator_attestation=operator,
                    intended_device_udid_file=private_id,
                    operator_validator=self.operator_validator,
                    now_utc=self.NOW,
                    profile_probe=rejected_profile,
                    device_probe=self.device_probe,
                    state_dir=state,
                )
            self.assertFalse(state.exists())

    def test_live_device_install_must_be_verified_before_consumption(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            private_id = self.write_private_udid(root)
            operator = root / "operator.json"
            operator.write_text("{}", encoding="utf-8")
            state = root / "state"

            with self.assertRaisesRegex(
                rendezvous.PrivateFieldRendezvousError,
                "live intended-device probe was not verified",
            ):
                rendezvous.verify_private_field_rendezvous(
                    candidate_root=root / "candidate",
                    candidate=self.candidate(),
                    operator_attestation=operator,
                    intended_device_udid_file=private_id,
                    operator_validator=self.operator_validator,
                    now_utc=self.NOW,
                    profile_probe=self.profile_probe,
                    device_probe=lambda udid: {"connectedDeviceProbeVerified": False},
                    state_dir=state,
                )
            self.assertFalse(state.exists())

    def make_ipa(self, root: Path, profile: bytes, *, collision: bool = False):
        ipa = root / "candidate" / rendezvous.IPA_RELATIVE_PATH
        ipa.parent.mkdir(parents=True)
        with zipfile.ZipFile(ipa, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("Payload/Nembra.app/embedded.mobileprovision", profile)
            archive.writestr("Payload/Nembra.app/Info.plist", b"plist")
            if collision:
                archive.writestr("payload/nembra.app/EMBEDDED.mobileprovision", profile)
        raw = ipa.read_bytes()
        candidate = self.candidate(
            ipa_sha=hashlib.sha256(raw).hexdigest(),
            ipa_size=len(raw),
        )
        candidate["provisioningProfileSHA256"] = hashlib.sha256(profile).hexdigest()
        return ipa, candidate

    def test_exact_retained_ipa_and_profile_share_one_verified_subject(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            profile = b"private-mobileprovision-subject"
            ipa, candidate = self.make_ipa(root, profile)
            returned_path, returned_profile = rendezvous._stable_ipa_and_profile(
                root / "candidate",
                candidate,
            )
            self.assertEqual(returned_path, ipa)
            self.assertEqual(returned_profile, profile)

    def test_retained_ipa_rejects_casefolding_zip_collisions(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _, candidate = self.make_ipa(
                root,
                b"private-mobileprovision-subject",
                collision=True,
            )
            with self.assertRaisesRegex(
                rendezvous.PrivateFieldRendezvousError,
                "duplicate/colliding",
            ):
                rendezvous._stable_ipa_and_profile(root / "candidate", candidate)

    def test_provisioning_membership_uses_private_udid_and_exact_profile(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            profile = b"private-mobileprovision-subject"
            _, candidate = self.make_ipa(root, profile)
            decoded = {
                "UUID": "PROFILE-UUID",
                "ExpirationDate": self.NOW + timedelta(days=30),
                "TeamIdentifier": ["ABCDE12345"],
                "Entitlements": {
                    "application-identifier": f"ABCDE12345.{rendezvous.BUNDLE_ID}",
                },
                "ProvisionedDevices": [self.UDID],
            }
            with mock.patch.object(
                rendezvous,
                "_decode_mobileprovision",
                return_value=decoded,
            ):
                subject = rendezvous._verify_profile_membership(
                    candidate_root=root / "candidate",
                    candidate=candidate,
                    intended_device_udid=self.UDID,
                    now_utc=self.NOW,
                )
                self.assertTrue(subject["intendedDeviceMembershipVerified"])
                self.assertEqual(
                    subject["provisioningMembershipMode"],
                    "explicit-provisioned-device",
                )
                with self.assertRaisesRegex(
                    rendezvous.PrivateFieldRendezvousError,
                    "not admitted",
                ):
                    rendezvous._verify_profile_membership(
                        candidate_root=root / "candidate",
                        candidate=candidate,
                        intended_device_udid="00008101-FFFFFFFFFFFFFFFF",
                        now_utc=self.NOW,
                    )

    def test_device_commitment_is_stable_and_device_specific(self):
        self.assertEqual(
            rendezvous._device_commitment(self.UDID),
            rendezvous._device_commitment(self.UDID),
        )
        self.assertNotEqual(
            rendezvous._device_commitment(self.UDID),
            rendezvous._device_commitment("00008101-FFFFFFFFFFFFFFFF"),
        )
        self.assertNotIn(self.UDID, rendezvous._device_commitment(self.UDID))

    def test_default_live_device_probe_fails_closed_off_macos(self):
        if rendezvous.sys.platform == "darwin":
            self.skipTest("production probe is intentionally macOS-only")
        with self.assertRaisesRegex(
            rendezvous.PrivateFieldRendezvousError,
            "requires macOS",
        ):
            rendezvous._verify_live_device_install(self.UDID)


if __name__ == "__main__":
    unittest.main()
