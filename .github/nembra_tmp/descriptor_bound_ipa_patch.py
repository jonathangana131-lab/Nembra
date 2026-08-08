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
    expected_sha256: str,
) -> Path:
    """Extract the exact pre-measured IPA through one already-open no-follow descriptor."""
    if not SHA256_RE.fullmatch(expected_sha256):
        raise EvidenceError("exact IPA inspection subject expected SHA-256 is malformed")
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

        pre_sha256, pre_count = _sha256_descriptor(descriptor)
        after_pre_hash = os.fstat(descriptor)
        if (
            _stable_file_identity(before) != _stable_file_identity(after_pre_hash)
            or pre_count != before.st_size
            or pre_sha256 != expected_sha256
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
        post_sha256, post_count = _sha256_descriptor(descriptor)
        after_post_hash = os.fstat(descriptor)
        if (
            _stable_file_identity(before) != _stable_file_identity(after_extract)
            or _stable_file_identity(after_extract) != _stable_file_identity(after_post_hash)
            or post_count != pre_count
            or post_sha256 != pre_sha256
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
    return app_path

'''
text = text[:start] + replacement + text[end + 1:]

old_call = "        app_path = extract_ipa_safely(ipa_path, root)\n"
new_call = '''        app_path = extract_ipa_safely(
            ipa_path,
            root,
            expected_identity=ipa_identity_before,
            expected_sha256=ipa_sha,
        )
'''
if text.count(old_call) != 1:
    raise SystemExit("unexpected extract_ipa_safely call site")
text = text.replace(old_call, new_call, 1)
inspector_path.write_text(text, encoding="utf-8")

new_tests = '''#!/usr/bin/env python3
"""Adversarial regressions for exact signed-IPA subject binding.

The field inspector must bind the pre-measured digest, ZIP extraction, and later signing facts to
one exact filesystem subject even when an attacker can replace the pathname concurrently.
"""

from __future__ import annotations

import hashlib
import importlib.util
import io
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
    def test_path_swap_after_open_cannot_steer_descriptor_extraction(self) -> None:
        inspector = load_inspector()
        original_ipa = make_minimal_ipa(b"original exact subject")
        transient_ipa = make_minimal_ipa(b"transient pathname replacement")

        with tempfile.TemporaryDirectory(prefix="nembra-descriptor-subject-test-") as temporary:
            root = Path(temporary)
            subject_path = root / "NembraField.ipa"
            held_original = root / "held-original.ipa"
            extraction_root = root / "extract"
            subject_path.write_bytes(original_ipa)
            subject_path.chmod(0o400)

            expected_identity = inspector._stable_file_identity(subject_path.lstat())
            expected_sha256 = hashlib.sha256(original_ipa).hexdigest()
            real_descriptor_hash = inspector._sha256_descriptor
            first_hash = True

            def replace_path_after_descriptor_open(descriptor: int):
                nonlocal first_hash
                if first_hash:
                    first_hash = False
                    subject_path.rename(held_original)
                    subject_path.write_bytes(transient_ipa)
                return real_descriptor_hash(descriptor)

            with patch.object(
                inspector,
                "_sha256_descriptor",
                side_effect=replace_path_after_descriptor_open,
            ):
                app_path = inspector.extract_ipa_safely(
                    subject_path,
                    extraction_root,
                    expected_identity=expected_identity,
                    expected_sha256=expected_sha256,
                )

            self.assertEqual((app_path / "marker.bin").read_bytes(), b"original exact subject")
            self.assertEqual(subject_path.read_bytes(), transient_ipa)
            self.assertEqual(held_original.read_bytes(), original_ipa)

    def test_path_swap_before_open_fails_closed(self) -> None:
        inspector = load_inspector()
        original_ipa = make_minimal_ipa(b"original exact subject")
        transient_ipa = make_minimal_ipa(b"transient pathname replacement")

        with tempfile.TemporaryDirectory(prefix="nembra-descriptor-preopen-test-") as temporary:
            root = Path(temporary)
            subject_path = root / "NembraField.ipa"
            held_original = root / "held-original.ipa"
            subject_path.write_bytes(original_ipa)
            subject_path.chmod(0o400)
            expected_identity = inspector._stable_file_identity(subject_path.lstat())
            expected_sha256 = hashlib.sha256(original_ipa).hexdigest()

            subject_path.rename(held_original)
            subject_path.write_bytes(transient_ipa)

            with self.assertRaisesRegex(
                inspector.EvidenceError,
                "changed before descriptor-bound extraction",
            ):
                inspector.extract_ipa_safely(
                    subject_path,
                    root / "extract",
                    expected_identity=expected_identity,
                    expected_sha256=expected_sha256,
                )

    def test_in_place_mutation_during_extraction_fails_closed(self) -> None:
        inspector = load_inspector()
        original_ipa = make_minimal_ipa(b"original exact subject")

        with tempfile.TemporaryDirectory(prefix="nembra-descriptor-mutation-test-") as temporary:
            root = Path(temporary)
            subject_path = root / "NembraField.ipa"
            subject_path.write_bytes(original_ipa)
            subject_path.chmod(0o400)
            expected_identity = inspector._stable_file_identity(subject_path.lstat())
            expected_sha256 = hashlib.sha256(original_ipa).hexdigest()
            real_copyfileobj = inspector.shutil.copyfileobj
            mutated = False

            def mutate_after_member_copy(source, sink, *args, **kwargs):
                nonlocal mutated
                result = real_copyfileobj(source, sink, *args, **kwargs)
                if not mutated:
                    mutated = True
                    subject_path.chmod(0o600)
                    with subject_path.open("ab") as handle:
                        handle.write(b"mutation")
                return result

            with patch.object(inspector.shutil, "copyfileobj", side_effect=mutate_after_member_copy):
                with self.assertRaisesRegex(
                    inspector.EvidenceError,
                    "changed during descriptor-bound extraction",
                ):
                    inspector.extract_ipa_safely(
                        subject_path,
                        root / "extract",
                        expected_identity=expected_identity,
                        expected_sha256=expected_sha256,
                    )


if __name__ == "__main__":
    unittest.main()
'''
test_path.write_text(new_tests, encoding="utf-8")
