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

    def canonical_document(self) -> bytes:
        return rendezvous.canonical_json_bytes(self.value)

    def write_document(self, root: Path, name: str = "rendezvous.json") -> Path:
        path = root / name
        path.write_bytes(self.canonical_document())
        path.chmod(0o600)
        return path.resolve()

    def test_canonical_round_trip_is_closed_and_nonauthorizing(self) -> None:
        data = self.canonical_document()
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

    def test_regular_single_link_document_is_read_from_one_descriptor(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write_document(Path(temporary).resolve())
            data = rendezvous._read_exact(path)
        self.assertEqual(data, self.canonical_document())

    def test_final_symlink_is_rejected_without_following_it(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            target = self.write_document(root, "target.json")
            link = root / "rendezvous.json"
            link.symlink_to(target)
            with self.assertRaises(rendezvous.SignerRendezvousError):
                rendezvous._read_exact(link)

    def test_parent_symlink_is_rejected_without_path_reopen(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            real = root / "real"
            real.mkdir(mode=0o700)
            self.write_document(real)
            alias = root / "alias"
            alias.symlink_to(real, target_is_directory=True)
            with self.assertRaises(rendezvous.SignerRendezvousError):
                rendezvous._read_exact(alias / "rendezvous.json")

    def test_hard_link_alias_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            target = self.write_document(root, "target.json")
            alias = root / "rendezvous.json"
            os.link(target, alias)
            with self.assertRaises(rendezvous.SignerRendezvousError):
                rendezvous._read_exact(alias)

    def test_group_or_world_writable_document_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            path = self.write_document(root)
            path.chmod(0o620)
            with self.assertRaises(rendezvous.SignerRendezvousError):
                rendezvous._read_exact(path)

    def test_source_never_reopens_validated_path_with_pathlib(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn('getattr(os, "O_NOFOLLOW", None)', source)
        self.assertIn("os.fstat(descriptor)", source)
        self.assertIn("identity(after) != identity(before)", source)
        self.assertNotIn("candidate.read_bytes()", source)
        self.assertNotIn("candidate.is_file()", source)
        self.assertNotIn("candidate.is_symlink()", source)


if __name__ == "__main__":
    unittest.main()
