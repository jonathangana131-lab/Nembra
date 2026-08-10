from pathlib import Path

source_path = Path("Scripts/capture_tuya_private_input_provenance.py")
source = source_path.read_text(encoding="utf-8")

old = 'def _read_stable_regular_file_sha256(path: Path) -> tuple[os.stat_result, str]:\n'
new = '''def _read_stable_regular_file_sha256(
    path: Path,
    *,
    expected_identity: tuple[int, ...] | None = None,
) -> tuple[os.stat_result, str]:
'''
if source.count(old) != 1:
    raise SystemExit("stable file reader signature seam did not match once")
source = source.replace(old, new, 1)

old = '''        if not stat.S_ISREG(before.st_mode):
            raise ProvenanceError(f"required private build input is not a regular file: {path.name}")

        digest = hashlib.sha256()
'''
new = '''        if not stat.S_ISREG(before.st_mode):
            raise ProvenanceError(f"required private build input is not a regular file: {path.name}")

        before_identity = _stat_identity(before)
        if expected_identity is not None and before_identity != expected_identity:
            raise ProvenanceError("private build tree changed before an admitted file was opened")

        digest = hashlib.sha256()
'''
if source.count(old) != 1:
    raise SystemExit("descriptor admission seam did not match once")
source = source.replace(old, new, 1)

old = '''        after = os.fstat(descriptor)
        if _stat_identity(before) != _stat_identity(after) or bytes_read != after.st_size:
            raise ProvenanceError(f"private build input changed while it was fingerprinted: {path.name}")

        try:
'''
new = '''        after = os.fstat(descriptor)
        after_identity = _stat_identity(after)
        if before_identity != after_identity or bytes_read != after.st_size:
            raise ProvenanceError(f"private build input changed while it was fingerprinted: {path.name}")
        if expected_identity is not None and after_identity != expected_identity:
            raise ProvenanceError("private build tree changed while an admitted file was fingerprinted")

        try:
'''
if source.count(old) != 1:
    raise SystemExit("descriptor post-read seam did not match once")
source = source.replace(old, new, 1)

old = '''def _file_fingerprint(path: Path) -> str:
    metadata, content_sha256 = _read_stable_regular_file_sha256(path)
'''
new = '''def _file_fingerprint(
    path: Path,
    *,
    expected_identity: tuple[int, ...] | None = None,
) -> str:
    metadata, content_sha256 = _read_stable_regular_file_sha256(
        path,
        expected_identity=expected_identity,
    )
'''
if source.count(old) != 1:
    raise SystemExit("file fingerprint signature seam did not match once")
source = source.replace(old, new, 1)

old = '                fingerprint = _file_fingerprint(path)\n'
new = '                fingerprint = _file_fingerprint(path, expected_identity=identity)\n'
if source.count(old) != 1:
    raise SystemExit("tree file fingerprint admission seam did not match once")
source = source.replace(old, new, 1)
source_path.write_text(source, encoding="utf-8")

test_path = Path("scripts/ci/tests/test_capture_tuya_private_input_provenance.py")
test = test_path.read_text(encoding="utf-8")

old = '''        def fingerprint_then_replace(path: Path) -> str:
            nonlocal replaced
            result = original_fingerprint(path)
'''
new = '''        def fingerprint_then_replace(path: Path, **kwargs: object) -> str:
            nonlocal replaced
            result = original_fingerprint(path, **kwargs)
'''
if test.count(old) != 1:
    raise SystemExit("replacement-race mock seam did not match once")
test = test.replace(old, new, 1)

old = '''        def fingerprint_then_add(path: Path) -> str:
            nonlocal added
            result = original_fingerprint(path)
'''
new = '''        def fingerprint_then_add(path: Path, **kwargs: object) -> str:
            nonlocal added
            result = original_fingerprint(path, **kwargs)
'''
if test.count(old) != 1:
    raise SystemExit("addition-race mock seam did not match once")
test = test.replace(old, new, 1)

marker = '''    def test_tree_rejects_entry_added_after_directory_enumeration(self) -> None:
'''
regression = '''    def test_tree_binds_open_descriptor_to_enumerated_file_identity(self) -> None:
        target = self.security_build / "ThingSmartCryption.bin"
        replacement = self.root / "replacement-before-open.bin"
        replacement.write_bytes(b"attacker-replacement-bytes")
        original_open = provenance.os.open
        original_lstat = Path.lstat
        substituted_open = False
        post_open_target_lstat_calls = 0

        def open_replacement(path: object, flags: int, *args: object, **kwargs: object) -> int:
            nonlocal substituted_open
            if Path(path) == target:
                substituted_open = True
                return original_open(replacement, flags, *args, **kwargs)
            return original_open(path, flags, *args, **kwargs)

        def lstat_aba(path: Path) -> os.stat_result:
            nonlocal post_open_target_lstat_calls
            if path == target and substituted_open and post_open_target_lstat_calls == 0:
                post_open_target_lstat_calls += 1
                return original_lstat(replacement)
            return original_lstat(path)

        with mock.patch.object(provenance.os, "open", side_effect=open_replacement), mock.patch.object(
            Path, "lstat", autospec=True, side_effect=lstat_aba
        ):
            with self.assertRaises(provenance.ProvenanceError):
                provenance._tree_fingerprint(self.security_build)

        self.assertTrue(substituted_open)
        self.assertEqual(target.read_bytes(), b"security-bytes-v1")

'''
if test.count(marker) != 1:
    raise SystemExit("tree addition test marker did not match once")
if "test_tree_binds_open_descriptor_to_enumerated_file_identity" in test:
    raise SystemExit("descriptor identity regression already exists")
test = test.replace(marker, regression + marker, 1)
test_path.write_text(test, encoding="utf-8")

final = source_path.read_text(encoding="utf-8")
assert "expected_identity: tuple[int, ...] | None = None" in final
assert "before_identity != expected_identity" in final
assert "after_identity != expected_identity" in final
assert "_file_fingerprint(path, expected_identity=identity)" in final
print("private tree descriptor identity repair materialized")
