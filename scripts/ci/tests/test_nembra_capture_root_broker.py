#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import stat
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[3]
BROKER_PATH = ROOT / "scripts/field/nembra_capture_root_broker.py"
SPEC = importlib.util.spec_from_file_location("nembra_capture_root_broker", BROKER_PATH)
assert SPEC is not None and SPEC.loader is not None
broker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(broker)


SOURCE_SHA = "a" * 40
ENTRY = "selected-xcode-build-orchestrator"
HELPER = "signed-app-origin-custody"
ENTRY_PAYLOAD = b"print('approved entry')\n"
HELPER_PAYLOAD = b"print('approved helper')\n"


def contract(payload: bytes) -> dict[str, str]:
    return {"sha256": hashlib.sha256(payload).hexdigest(), "kind": "python-root"}


def policy_dict() -> dict[str, object]:
    return {
        "schema": 1,
        "authorizedSourceSHA": SOURCE_SHA,
        "entrySubject": ENTRY,
        "subjects": {
            ENTRY: contract(ENTRY_PAYLOAD),
            HELPER: contract(HELPER_PAYLOAD),
        },
    }


def policy_bytes() -> bytes:
    return (json.dumps(policy_dict(), sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def bundle_dict(*, source_sha: str = SOURCE_SHA) -> dict[str, object]:
    return {
        "schema": 1,
        "sourceSHA": source_sha,
        "subjects": {
            ENTRY: base64.b64encode(ENTRY_PAYLOAD).decode("ascii"),
            HELPER: base64.b64encode(HELPER_PAYLOAD).decode("ascii"),
        },
    }


def bundle_bytes(**kwargs) -> bytes:
    return (json.dumps(bundle_dict(**kwargs), sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


class CaptureRootBrokerPolicyTests(unittest.TestCase):
    def test_valid_complete_bundle_is_accepted(self) -> None:
        policy = broker._parse_policy_bytes(policy_bytes())
        approved = broker._parse_and_authorize_bundle(policy, bundle_bytes())
        self.assertEqual(set(approved), {ENTRY, HELPER})
        self.assertEqual(approved[ENTRY], ENTRY_PAYLOAD)
        self.assertEqual(approved[HELPER], HELPER_PAYLOAD)

    def test_payload_digest_mismatch_fails_closed(self) -> None:
        policy = broker._parse_policy_bytes(policy_bytes())
        value = bundle_dict()
        subjects = value["subjects"]
        assert isinstance(subjects, dict)
        subjects[HELPER] = base64.b64encode(HELPER_PAYLOAD + b"# field mutation\n").decode("ascii")
        with self.assertRaisesRegex(broker.BrokerError, "bytes do not match administrator policy"):
            broker._parse_and_authorize_bundle(policy, json.dumps(value).encode("utf-8"))

    def test_source_sha_mismatch_fails_closed(self) -> None:
        policy = broker._parse_policy_bytes(policy_bytes())
        with self.assertRaisesRegex(broker.BrokerError, "source SHA is not administrator-authorized"):
            broker._parse_and_authorize_bundle(policy, bundle_bytes(source_sha="b" * 40))

    def test_missing_or_extra_privileged_subject_fails_closed(self) -> None:
        policy = broker._parse_policy_bytes(policy_bytes())
        for mutate in ("missing", "extra"):
            value = bundle_dict()
            subjects = value["subjects"]
            assert isinstance(subjects, dict)
            if mutate == "missing":
                subjects.pop(HELPER)
            else:
                subjects["candidate-extra-root"] = base64.b64encode(b"print('attacker')\n").decode("ascii")
            with self.assertRaisesRegex(broker.BrokerError, "exactly the administrator-authorized"):
                broker._parse_and_authorize_bundle(policy, json.dumps(value).encode("utf-8"))

    def test_policy_selects_entry_subject_and_entry_must_be_authorized(self) -> None:
        policy = broker._parse_policy_bytes(policy_bytes())
        self.assertEqual(policy["entrySubject"], ENTRY)
        value = policy_dict()
        value["entrySubject"] = "not-authorized"
        with self.assertRaisesRegex(broker.BrokerError, "entry subject is not one authorized subject"):
            broker._parse_policy_bytes(json.dumps(value).encode("utf-8"))

    def test_duplicate_json_key_is_rejected_in_policy_or_bundle(self) -> None:
        policy_raw = (
            '{"schema":1,"schema":1,"authorizedSourceSHA":"'
            + SOURCE_SHA
            + '","entrySubject":"'
            + ENTRY
            + '","subjects":{}}'
        ).encode("utf-8")
        with self.assertRaisesRegex(broker.BrokerError, "duplicate key"):
            broker._parse_policy_bytes(policy_raw)

        bundle_raw = (
            '{"schema":1,"sourceSHA":"'
            + SOURCE_SHA
            + '","sourceSHA":"'
            + SOURCE_SHA
            + '","subjects":{}}'
        ).encode("utf-8")
        policy = broker._parse_policy_bytes(policy_bytes())
        with self.assertRaisesRegex(broker.BrokerError, "duplicate key"):
            broker._parse_and_authorize_bundle(policy, bundle_raw)

    def test_unknown_policy_root_field_is_rejected(self) -> None:
        value = policy_dict()
        value["candidateMayAuthorizeItself"] = True
        with self.assertRaisesRegex(broker.BrokerError, "missing or unknown fields"):
            broker._parse_policy_bytes(json.dumps(value).encode("utf-8"))

    def test_unknown_subject_contract_field_is_rejected(self) -> None:
        value = policy_dict()
        subjects = value["subjects"]
        assert isinstance(subjects, dict)
        item = subjects[HELPER]
        assert isinstance(item, dict)
        item["pathFromCheckout"] = "scripts/field/attacker.py"
        with self.assertRaisesRegex(broker.BrokerError, "missing or unknown fields"):
            broker._parse_policy_bytes(json.dumps(value).encode("utf-8"))

    def test_policy_must_authorize_at_least_one_bounded_subject(self) -> None:
        value = policy_dict()
        value["subjects"] = {}
        with self.assertRaisesRegex(broker.BrokerError, "subject count is invalid"):
            broker._parse_policy_bytes(json.dumps(value).encode("utf-8"))

    def test_subject_transport_is_strict_base64_and_bounded(self) -> None:
        self.assertEqual(
            broker._decode_subject_payload(base64.b64encode(ENTRY_PAYLOAD).decode("ascii"), name=ENTRY),
            ENTRY_PAYLOAD,
        )
        with self.assertRaisesRegex(broker.BrokerError, "not strict base64"):
            broker._decode_subject_payload(base64.b64encode(ENTRY_PAYLOAD).decode("ascii") + "!", name=ENTRY)
        oversized = base64.b64encode(b"x" * (broker.MAX_SUBJECT_BYTES + 1)).decode("ascii")
        with self.assertRaisesRegex(broker.BrokerError, "byte count is invalid"):
            broker._decode_subject_payload(oversized, name=ENTRY)

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
        self.assertEqual(broker._validate_subject_arguments(["--mode", "field"]), ["--mode", "field"])
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

    def test_policy_and_entry_are_not_cli_selectable(self) -> None:
        self.assertEqual(str(broker.POLICY_PATH), "/Library/NembraCaptureAuthority/v1/policy.json")
        parsed = broker._parse(["--", "--field-operation", "validate-only"])
        self.assertFalse(hasattr(parsed, "policy"))
        self.assertFalse(hasattr(parsed, "subject"))
        self.assertEqual(parsed.subject_arguments, ["--field-operation", "validate-only"])

    def test_approved_mapping_is_immutable_and_exposed_to_entry(self) -> None:
        policy = broker._parse_policy_bytes(policy_bytes())
        approved = broker._parse_and_authorize_bundle(policy, bundle_bytes())
        with self.assertRaises(TypeError):
            approved[ENTRY] = b"attacker"  # type: ignore[index]

    def test_source_requires_isolated_python_and_has_no_self_install_or_product_operation(self) -> None:
        source = BROKER_PATH.read_text(encoding="utf-8")
        self.assertIn("sys.flags.isolated == 1", source)
        self.assertIn("NEMBRA_APPROVED_ROOT_SUBJECTS", source)
        self.assertIn("set(encoded_subjects) == set(policy_subjects)", source)
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
            "git cat-file",
        )
        for marker in forbidden:
            self.assertNotIn(marker, source, marker)


if __name__ == "__main__":
    unittest.main()
