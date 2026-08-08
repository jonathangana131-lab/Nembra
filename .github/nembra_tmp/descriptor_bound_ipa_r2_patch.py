#!/usr/bin/env python3
from pathlib import Path

inspector_path = Path("scripts/ci/es80_signed_field_artifact_evidence.py")
test_path = Path("scripts/ci/tests/test_es80_signed_field_artifact_exact_subject.py")
text = inspector_path.read_text(encoding="utf-8")

start_marker = "def extract_ipa_safely(ipa_path: Path, destination: Path) -> Path:\n"
end_marker = "\ndef read_info_plist(app_path: Path) -> tuple[dict, Path]:\n"
if text.count(start_marker) != 1 or text.count(end_marker) != 1:
    raise SystemExit("unexpected extract_ipa_safely anchors")
start = text.index(start_marker)
end = text.index(end_marker, start)
replacement = '''def extract_ipa_safely(
    ipa_path: Path,
    destination: Path,
    *,
    expected_identity: tuple[int, int, int, int, int, int],
) -> tuple[Path, str, int]:
    """Hash and extract one exact IPA through one already-open no-follow descriptor."""
    if not hasattr(os, "O_NOFOLLOW"):
        raise EvidenceError("platform cannot enforce no-follow exact IPA inspection input")
    flags = os.O_RDONLY | os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    try:
        descriptor = os.open(ipa_path, flags)
    except OSError as exc:
        raise EvidenceError("could not open exact IPA inspection subject for extraction") from exc

    app_roots: set[str] = set()
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_size <= 0:
            raise EvidenceError("exact IPA inspection subject must remain one non-empty regular file")
        if _stable_file_identity(before) != expected_identity:
            raise EvidenceError("exact IPA inspection subject changed before descriptor-bound extraction")

        ipa_sha256, ipa_byte_count = _sha256_descriptor(descriptor)
        after_pre_hash = os.fstat(descriptor)
        if (
            _stable_file_identity(before) != _stable_file_identity(after_pre_hash)
            or ipa_byte_count != before.st_size
            or not SHA256_RE.fullmatch(ipa_sha256)
        ):
            raise EvidenceError("exact IPA inspection subject changed before descriptor-bound extraction")

        os.lseek(descriptor, 0, os.SEEK_SET)
        try:
            subject = os.fdopen(os.dup(descriptor), "rb")
        except OSError as exc:
            raise EvidenceError("could not duplicate exact IPA inspection descriptor") from exc
        with subject:
            try:
                archive = zipfile.ZipFile(subject)
            except (OSError, zipfile.BadZipFile) as exc:
                raise EvidenceError("input is not a readable IPA/ZIP archive") from exc

            with archive:
                infos = archive.infolist()
                validated_paths = _validated_unique_member_paths(infos)
                for info in infos:
                    member = validated_paths[info.filename]
                    mode = (info.external_attr >> 16) & 0o177777
                    if stat.S_ISLNK(mode):
                        raise EvidenceError(f"IPA contains unsupported symbolic-link member: {info.filename}")

                    parts = member.parts
                    if len(parts) >= 2 and parts[0] == "Payload" and parts[1].endswith(".app"):
                        app_roots.add(parts[1])

                    target = destination.joinpath(*parts)
                    resolved_parent = target.parent.resolve()
                    if destination.resolve() not in (resolved_parent, *resolved_parent.parents):
                        raise EvidenceError(f"IPA member escapes extraction root: {info.filename}")

                    if info.is_dir():
                        target.mkdir(parents=True, exist_ok=True)
                        continue

                    target.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(info, "r") as source, target.open("wb") as sink:
                        shutil.copyfileobj(source, sink)
                    permissions = mode & 0o777
                    if permissions:
                        target.chmod(permissions)

        after_extract = os.fstat(descriptor)
        post_sha256, post_byte_count = _sha256_descriptor(descriptor)
        after_post_hash = os.fstat(descriptor)
        if (
            _stable_file_identity(before) != _stable_file_identity(after_extract)
            or _stable_file_identity(after_extract) != _stable_file_identity(after_post_hash)
            or post_byte_count != ipa_byte_count
            or post_sha256 != ipa_sha256
        ):
            raise EvidenceError("exact IPA inspection subject changed during descriptor-bound extraction")
    finally:
        os.close(descriptor)

    if len(app_roots) != 1:
        raise EvidenceError(
            f"IPA must contain exactly one top-level Payload/*.app bundle; found {sorted(app_roots)!r}"
        )
    app_path = destination / "Payload" / next(iter(app_roots))
    if not app_path.is_dir():
        raise EvidenceError("IPA app bundle was not extracted as a directory")
    return app_path, ipa_sha256, ipa_byte_count

'''
text = text[:start] + replacement + text[end + 1:]

old_preamble = '''    ipa_identity_before = _stable_file_identity(ipa_stat_before)

    ipa_sha = sha256_file(ipa_path)
    ipa_size = ipa_stat_before.st_size
    if not SHA256_RE.fullmatch(ipa_sha):
        raise EvidenceError("could not derive canonical IPA SHA-256")

    with tempfile.TemporaryDirectory(prefix="nembra-field-ipa-") as temporary:
        root = Path(temporary)
        app_path = extract_ipa_safely(ipa_path, root)
'''
new_preamble = '''    ipa_identity_before = _stable_file_identity(ipa_stat_before)

    with tempfile.TemporaryDirectory(prefix="nembra-field-ipa-") as temporary:
        root = Path(temporary)
        app_path, ipa_sha, ipa_size = extract_ipa_safely(
            ipa_path,
            root,
            expected_identity=ipa_identity_before,
        )
        if not SHA256_RE.fullmatch(ipa_sha):
            raise EvidenceError("could not derive canonical IPA SHA-256")
'''
if text.count(old_preamble) != 1:
    raise SystemExit("unexpected snapshotted IPA preamble")
text = text.replace(old_preamble, new_preamble, 1)
inspector_path.write_text(text, encoding="utf-8")

test_path.write_text('''#!/usr/bin/env python3
"""Adversarial regressions for exact signed-IPA subject binding."""

from __future__ import annotations

import hashlib
import importlib.util
import io
import os
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "es80_signed_field_artifact_evidence.py"


def load_inspector():
    spec = importlib.util.spec_from_file_location("nembra_signed_field_exact_subject", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load signed-field inspector")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_minimal_ipa(marker: bytes) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("Payload/Nembra.app/marker.bin", marker)
    return buffer.getvalue()


class SignedFieldArtifactExactSubjectTests(unittest.TestCase):
    def test_evidence_digest_comes_from_descriptor_bound_extractor(self) -> None:
        inspector = load_inspector()
        source_sha = "a" * 40
        original_ipa = b"exact signed candidate bytes"

        with tempfile.TemporaryDirectory(prefix="nembra-exact-subject-test-") as temporary:
            root = Path(temporary)
            ipa_path = root / "candidate.ipa"
            ipa_path.write_bytes(original_ipa)

            app_path = root / "fake" / "Payload" / "Nembra.app"
            app_path.mkdir(parents=True)
            executable_path = app_path / "Nembra"
            executable_path.write_bytes(b"signed executable fixture")
            info_path = app_path / "Info.plist"
            info_path.write_bytes(b"signed info plist fixture")
            info = {
                "CFBundleIdentifier": inspector.BUNDLE_ID,
                "DTPlatformName": "iphoneos",
                "CFBundleSupportedPlatforms": ["iPhoneOS"],
                "NembraCaptureBuildIdentifier": inspector.expected_build_identifier(source_sha),
                "NembraCaptureBuildInstanceID": "12345678-1234-4abc-8def-1234567890ab",
                "NembraCaptureBuildCommitSHA": source_sha,
                "CFBundleExecutable": "Nembra",
            }
            observed_inputs: list[tuple[bytes, tuple[int, int, int, int, int, int]]] = []

            def observing_extract(path: Path, destination: Path, *, expected_identity):
                observed_inputs.append((path.read_bytes(), expected_identity))
                return app_path, hashlib.sha256(original_ipa).hexdigest(), len(original_ipa)

            with (
                patch.object(inspector, "extract_ipa_safely", side_effect=observing_extract),
                patch.object(inspector, "reject_embedded_external_authority"),
                patch.object(inspector, "read_info_plist", return_value=(info, info_path)),
                patch.object(inspector, "verify_device_platform", return_value=("iphoneos", ["iPhoneOS"])),
                patch.object(inspector, "run_codesign", return_value=("ABCDE12345", ["Apple Development: Fixture"], "b" * 40)),
                patch.object(
                    inspector,
                    "verify_provisioning_profile",
                    return_value=("c" * 64, "PROFILE-UUID", "2099-01-01T00:00:00Z", f"ABCDE12345.{inspector.BUNDLE_ID}"),
                ),
            ):
                inspection = inspector.inspect_ipa(
                    ipa_path,
                    source_sha,
                    intended_device_udid="00008101-001234567890001E",
                )

            self.assertEqual(
                inspection["field_build_record"]["signedInstallableSHA256"],
                hashlib.sha256(original_ipa).hexdigest(),
            )
            self.assertEqual(len(observed_inputs), 1)
            self.assertEqual(observed_inputs[0][0], original_ipa)

    def test_path_replacement_before_descriptor_open_fails_closed(self) -> None:
        inspector = load_inspector()
        original_ipa = make_minimal_ipa(b"original")
        replacement_ipa = make_minimal_ipa(b"replacement")
        with tempfile.TemporaryDirectory(prefix="nembra-preopen-swap-test-") as temporary:
            root = Path(temporary)
            subject = root / "NembraField.ipa"
            held = root / "held.ipa"
            subject.write_bytes(original_ipa)
            subject.chmod(0o400)
            expected_identity = inspector._stable_file_identity(subject.lstat())
            subject.rename(held)
            subject.write_bytes(replacement_ipa)
            with self.assertRaisesRegex(inspector.EvidenceError, "changed before descriptor-bound extraction"):
                inspector.extract_ipa_safely(
                    subject,
                    root / "extract",
                    expected_identity=expected_identity,
                )

    def test_path_replacement_after_descriptor_hash_never_extracts_replacement(self) -> None:
        inspector = load_inspector()
        original_ipa = make_minimal_ipa(b"original exact subject")
        replacement_ipa = make_minimal_ipa(b"replacement pathname subject")
        with tempfile.TemporaryDirectory(prefix="nembra-postopen-swap-test-") as temporary:
            root = Path(temporary)
            subject = root / "NembraField.ipa"
            held = root / "held.ipa"
            extraction = root / "extract"
            subject.write_bytes(original_ipa)
            subject.chmod(0o400)
            expected_identity = inspector._stable_file_identity(subject.lstat())
            real_fdopen = os.fdopen
            replaced = False

            def replace_path_then_fdopen(descriptor: int, *args, **kwargs):
                nonlocal replaced
                if not replaced:
                    replaced = True
                    subject.rename(held)
                    subject.write_bytes(replacement_ipa)
                return real_fdopen(descriptor, *args, **kwargs)

            with patch.object(inspector.os, "fdopen", side_effect=replace_path_then_fdopen):
                try:
                    inspector.extract_ipa_safely(
                        subject,
                        extraction,
                        expected_identity=expected_identity,
                    )
                except inspector.EvidenceError as error:
                    self.assertIn("changed during descriptor-bound extraction", str(error))

            self.assertTrue(replaced)
            self.assertEqual((extraction / "Payload" / "Nembra.app" / "marker.bin").read_bytes(), b"original exact subject")
            self.assertEqual(subject.read_bytes(), replacement_ipa)

    def test_in_place_mutation_during_extraction_fails_closed(self) -> None:
        inspector = load_inspector()
        original_ipa = make_minimal_ipa(b"original exact subject")
        with tempfile.TemporaryDirectory(prefix="nembra-in-place-mutation-test-") as temporary:
            root = Path(temporary)
            subject = root / "NembraField.ipa"
            subject.write_bytes(original_ipa)
            subject.chmod(0o400)
            expected_identity = inspector._stable_file_identity(subject.lstat())
            real_copy = inspector.shutil.copyfileobj
            mutated = False

            def mutate_after_copy(source, sink, *args, **kwargs):
                nonlocal mutated
                result = real_copy(source, sink, *args, **kwargs)
                if not mutated:
                    mutated = True
                    subject.chmod(0o600)
                    with subject.open("ab") as handle:
                        handle.write(b"mutation")
                return result

            with patch.object(inspector.shutil, "copyfileobj", side_effect=mutate_after_copy):
                with self.assertRaisesRegex(inspector.EvidenceError, "changed during descriptor-bound extraction"):
                    inspector.extract_ipa_safely(
                        subject,
                        root / "extract",
                        expected_identity=expected_identity,
                    )


if __name__ == "__main__":
    unittest.main()
''', encoding="utf-8")
