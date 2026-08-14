#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import stat
import sys
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[3]
BROKER_PATH = ROOT / "scripts/field/nembra_capture_root_broker.py"
SPEC = importlib.util.spec_from_file_location("nembra_capture_root_broker", BROKER_PATH)
assert SPEC is not None and SPEC.loader is not None
broker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(broker)


SOURCE_SHA = "a" * 40
SUBJECT_NAME = "selected-xcode-build-orchestrator"
PAYLOAD = b"print('approved subject')\n"
PAYLOAD_SHA256 = hashlib.sha256(PAYLOAD).hexdigest()


def policy_dict(*, digest: str = PAYLOAD_SHA256) -> dict[str, object]:
    return {
        "schema": 1,
        "authorizedSourceSHA": SOURCE_SHA,
        "subjects": {
            SUBJECT_NAME: {
                "sha256": digest,
                "kind": "python-root",
            }
        },
    }


def policy_bytes(**kwargs) -> bytes:
    return (json.dumps(policy_dict(**kwargs), sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


class CaptureRootBrokerPolicyTests(unittest.TestCase):
    def test_valid_policy_and_subject_are_accepted(self) -> None:
        policy = broker._parse_policy_bytes(policy_bytes())
        approved = broker._authorize_subject(
            policy,
            source_sha=SOURCE_SHA,
            subject_name=SUBJECT_NAME,
            payload=PAYLOAD,
        )
        self.assertEqual(approved, PAYLOAD)

    def test_payload_digest_mismatch_fails_closed(self) -> None:
        policy = broker._parse_policy_bytes(policy_bytes())
        with self.assertRaisesRegex(broker.BrokerError, "bytes do not match administrator policy"):
            broker._authorize_subject(
                policy,
                source_sha=SOURCE_SHA,
                subject_name=SUBJECT_NAME,
                payload=PAYLOAD + b"# field mutation\n",
            )

    def test_source_sha_mismatch_fails_closed(self) -> None:
        policy = broker._parse_policy_bytes(policy_bytes())
        with self.assertRaisesRegex(broker.BrokerError, "source SHA is not administrator-authorized"):
            broker._authorize_subject(
                policy,
                source_sha="b" * 40,
                subject_name=SUBJECT_NAME,
                payload=PAYLOAD,
            )

    def test_unlisted_subject_fails_closed(self) -> None:
        policy = broker._parse_policy_bytes(policy_bytes())
        with self.assertRaisesRegex(broker.BrokerError, "root subject is not administrator-authorized"):
            broker._authorize_subject(
                policy,
                source_sha=SOURCE_SHA,
                subject_name="unlisted-root-helper",
                payload=PAYLOAD,
            )

    def test_duplicate_json_key_is_rejected(self) -> None:
        raw = (
            '{"schema":1,"schema":1,"authorizedSourceSHA":"'
            + SOURCE_SHA
            + '","subjects":{"'
            + SUBJECT_NAME
            + '":{"sha256":"'
            + PAYLOAD_SHA256
            + '","kind":"python-root"}}}'
        ).encode("utf-8")
        with self.assertRaisesRegex(broker.BrokerError, "duplicate key"):
            broker._parse_policy_bytes(raw)

    def test_unknown_policy_root_field_is_rejected(self) -> None:
        value = policy_dict()
        value["candidateMayAuthorizeItself"] = True
        raw = json.dumps(value).encode("utf-8")
        with self.assertRaisesRegex(broker.BrokerError, "missing or unknown fields"):
            broker._parse_policy_bytes(raw)

    def test_unknown_subject_contract_field_is_rejected(self) -> None:
        value = policy_dict()
        subjects = value["subjects"]
        assert isinstance(subjects, dict)
        contract = subjects[SUBJECT_NAME]
        assert isinstance(contract, dict)
        contract["pathFromCheckout"] = "scripts/field/attacker.py"
        raw = json.dumps(value).encode("utf-8")
        with self.assertRaisesRegex(broker.BrokerError, "missing or unknown fields"):
            broker._parse_policy_bytes(raw)

    def test_policy_must_authorize_at_least_one_bounded_subject(self) -> None:
        value = policy_dict()
        value["subjects"] = {}
        with self.assertRaisesRegex(broker.BrokerError, "subject count is invalid"):
            broker._parse_policy_bytes(json.dumps(value).encode("utf-8"))

    def test_subject_transport_is_strict_base64_and_bounded(self) -> None:
        encoded = base64.b64encode(PAYLOAD).decode("ascii")
        self.assertEqual(broker._decode_subject_payload(encoded), PAYLOAD)
        with self.assertRaisesRegex(broker.BrokerError, "not strict base64"):
            broker._decode_subject_payload(encoded + "!")
        oversized = base64.b64encode(b"x" * (broker.MAX_SUBJECT_BYTES + 1)).decode("ascii")
        with self.assertRaisesRegex(broker.BrokerError, "byte count is invalid"):
            broker._decode_subject_payload(oversized)

    def test_policy_file_contract_requires_root_regular_0444(self) -> None:
        valid = mock.Mock(st_mode=stat.S_IFREG | 0o444, st_uid=0, st_gid=0)
        broker._validate_policy_stat(valid)

        for bad in (
            mock.Mock(st_mode=stat.S_IFREG | 0o644, st_uid=0, st_gid=0),
            mock.Mock(st_mode=stat.S_IFREG | 0o444, st_uid=501, st_gid=0),
            mock.Mock(st_mode=stat.S_IFREG | 0o444, st_uid=0, st_gid=20),
            mock.Mock(st_mode=stat.S_IFLNK | 0o444, st_uid=0, st_gid=0),
        ):
            with self.assertRaises(broker.BrokerError):
                broker._validate_policy_stat(bad)

    def test_policy_directory_contract_rejects_field_writable_ancestry(self) -> None:
        valid = mock.Mock(st_mode=stat.S_IFDIR | 0o755, st_uid=0, st_gid=0)
        broker._validate_directory_stat(valid, "policy root")
        writable = mock.Mock(st_mode=stat.S_IFDIR | 0o775, st_uid=0, st_gid=0)
        with self.assertRaisesRegex(broker.BrokerError, "group/world writable"):
            broker._validate_directory_stat(writable, "policy root")

    def test_argument_transport_rejects_nul_and_excess(self) -> None:
        self.assertEqual(broker._validate_subject_arguments(["--source-sha", SOURCE_SHA]), ["--source-sha", SOURCE_SHA])
        with self.assertRaisesRegex(broker.BrokerError, "contains NUL"):
            broker._validate_subject_arguments(["ok\x00bad"])
        with self.assertRaisesRegex(broker.BrokerError, "argument count is excessive"):
            broker._validate_subject_arguments(["x"] * (broker.MAX_ARGUMENTS + 1))

    def test_environment_is_closed_except_sudo_identity(self) -> None:
        original = dict(broker.os.environ)
        try:
            broker.os.environ.clear()
            broker.os.environ.update(
                {
                    "SUDO_UID": "501",
                    "SUDO_GID": "20",
                    "SUDO_USER": "field-user",
                    "DEVELOPER_DIR": "/tmp/attacker-xcode",
                    "PYTHONPATH": "/tmp/attacker-python",
                    "DYLD_INSERT_LIBRARIES": "/tmp/attacker.dylib",
                }
            )
            broker._sanitize_root_environment()
            self.assertEqual(
                dict(broker.os.environ),
                {
                    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                    "LANG": "en_US.UTF-8",
                    "LC_ALL": "en_US.UTF-8",
                    "SUDO_UID": "501",
                    "SUDO_GID": "20",
                    "SUDO_USER": "field-user",
                },
            )
        finally:
            broker.os.environ.clear()
            broker.os.environ.update(original)

    def test_policy_path_is_compiled_and_not_cli_selectable(self) -> None:
        self.assertEqual(str(broker.POLICY_PATH), "/Library/NembraCaptureAuthority/v1/policy.json")
        parsed = broker._parse(
            [
                "--source-sha",
                SOURCE_SHA,
                "--subject",
                SUBJECT_NAME,
                "--payload-base64",
                base64.b64encode(PAYLOAD).decode("ascii"),
            ]
        )
        self.assertFalse(hasattr(parsed, "policy"))

    def test_source_contains_no_self_install_or_privileged_product_operation(self) -> None:
        source = BROKER_PATH.read_text(encoding="utf-8")
        forbidden = (
            "/usr/bin/sudo",
            "/usr/bin/dscl",
            "/usr/bin/xcodebuild",
            "devicectl",
            "xctrace",
            "CoreBluetooth",
            "CBCentralManager",
            "NEMBRA_TUYA_APP_KEY",
            "NEMBRA_TUYA_APP_SECRET",
            "--policy",
        )
        for marker in forbidden:
            self.assertNotIn(marker, source, marker)


if __name__ == "__main__":
    unittest.main()
