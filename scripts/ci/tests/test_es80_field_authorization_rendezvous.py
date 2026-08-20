import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_field_authorization_rendezvous.py"
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SWIFT_SOURCE = (
    REPOSITORY_ROOT
    / "Packages/NembraBluetoothCapture/Sources/NembraCaptureAppAuthorization"
    / "AuthenticatedStationaryCaptureSignerRendezvousDocument.swift"
)
SPEC = importlib.util.spec_from_file_location("signer_rendezvous", SCRIPT)
assert SPEC and SPEC.loader
rendezvous = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rendezvous)


class SignerRendezvousTests(unittest.TestCase):
    def setUp(self) -> None:
        self.start = 2_000_000
        self.value = {
            "schema": rendezvous.SCHEMA,
            "version": rendezvous.SCHEMA_VERSION,
            "procedureID": rendezvous.PROCEDURE_ID,
            "attemptChallengeSHA256": "a" * 64,
            "attemptStartedAtUnixMilliseconds": self.start,
            "authorizationMustExpireByUnixMilliseconds": (
                self.start + rendezvous.MAX_AUTHORIZATION_LIFETIME_MILLISECONDS
            ),
        }

    def test_canonical_round_trip_is_closed_and_nonauthorizing(self) -> None:
        data = rendezvous.canonical_json_bytes(self.value)
        decoded = rendezvous.verify_rendezvous_bytes(data)
        self.assertEqual(decoded, self.value)
        self.assertFalse(data.endswith(b"\n"))
        for forbidden in (
            b'"decision"', b'"GO"', b'"signature"', b'"authorizationID"',
            b'"deviceIdentifier"', b'"startedAtUptimeNanoseconds"',
        ):
            self.assertNotIn(forbidden, data)

    def test_deadline_must_be_attempt_relative_not_signer_relative(self) -> None:
        changed = dict(self.value)
        changed["authorizationMustExpireByUnixMilliseconds"] += 1
        with self.assertRaises(rendezvous.SignerRendezvousError):
            rendezvous.verify_rendezvous_bytes(rendezvous.canonical_json_bytes(changed))

    def test_open_duplicate_noncanonical_and_wrong_procedure_are_rejected(self) -> None:
        extra = dict(self.value)
        extra["extra"] = True
        with self.assertRaises(rendezvous.SignerRendezvousError):
            rendezvous.verify_rendezvous_bytes(rendezvous.canonical_json_bytes(extra))

        with self.assertRaises(rendezvous.SignerRendezvousError):
            rendezvous.verify_rendezvous_bytes(b'{"schema":"a","schema":"b"}')

        pretty = (json.dumps(self.value, indent=2, sort_keys=True) + "\n").encode()
        with self.assertRaises(rendezvous.SignerRendezvousError):
            rendezvous.verify_rendezvous_bytes(pretty)

        wrong = dict(self.value)
        wrong["procedureID"] = "wrong-procedure"
        with self.assertRaises(rendezvous.SignerRendezvousError):
            rendezvous.verify_rendezvous_bytes(rendezvous.canonical_json_bytes(wrong))

    def test_invalid_challenge_and_clock_are_rejected(self) -> None:
        for key, value in (
            ("attemptChallengeSHA256", "A" * 64),
            ("attemptChallengeSHA256", "a" * 63),
            ("attemptStartedAtUnixMilliseconds", 0),
        ):
            changed = dict(self.value)
            changed[key] = value
            if key == "attemptStartedAtUnixMilliseconds":
                changed["authorizationMustExpireByUnixMilliseconds"] = (
                    value + rendezvous.MAX_AUTHORIZATION_LIFETIME_MILLISECONDS
                )
            with self.subTest(key=key, value=value):
                with self.assertRaises(rendezvous.SignerRendezvousError):
                    rendezvous.verify_rendezvous_bytes(
                        rendezvous.canonical_json_bytes(changed)
                    )

    def test_descriptor_reader_returns_exact_canonical_file(self) -> None:
        data = rendezvous.canonical_json_bytes(self.value)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            path = root / "rendezvous.json"
            path.write_bytes(data)
            self.assertEqual(rendezvous._read_exact(path), data)

    def test_descriptor_reader_rejects_final_symlink_and_hardlink(self) -> None:
        data = rendezvous.canonical_json_bytes(self.value)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            target = root / "target.json"
            target.write_bytes(data)

            symlink = root / "symlink.json"
            symlink.symlink_to(target)
            with self.assertRaises(rendezvous.SignerRendezvousError):
                rendezvous._read_exact(symlink)

            hardlink = root / "hardlink.json"
            os.link(target, hardlink)
            with self.assertRaises(rendezvous.SignerRendezvousError):
                rendezvous._read_exact(hardlink)

    def test_reader_source_never_reopens_validated_path(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn('getattr(os, "O_NOFOLLOW", None)', source)
        self.assertIn("os.fstat(descriptor)", source)
        self.assertIn("before.st_nlink != 1", source)
        self.assertNotIn("candidate.read_bytes()", source)
        self.assertNotIn("candidate.is_file()", source)
        self.assertNotIn("candidate.is_symlink()", source)

    def test_python_wire_constants_match_swift_exporter(self) -> None:
        source = SWIFT_SOURCE.read_text(encoding="utf-8")
        self.assertIn(f'public static let schema = "{rendezvous.SCHEMA}"', source)
        self.assertIn(
            f"public static let schemaVersion = {rendezvous.SCHEMA_VERSION}", source
        )
        self.assertIn(
            f"public static let maximumDocumentByteCount = {rendezvous.MAX_DOCUMENT_BYTES:_}",
            source,
        )
        self.assertIn("maximumAuthorizationLifetimeMilliseconds", source)
        for key in rendezvous.KEYS:
            with self.subTest(key=key):
                self.assertIn(key, source)
        self.assertNotIn("startedAtUptimeNanoseconds:", source)


if __name__ == "__main__":
    unittest.main()