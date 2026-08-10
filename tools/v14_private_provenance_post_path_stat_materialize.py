from pathlib import Path

helper_path = Path("Scripts/capture_tuya_private_input_provenance.py")
source = helper_path.read_text(encoding="utf-8")
old = '''        try:
            current_path = path.lstat()
        except OSError as error:
            raise ProvenanceError(f"private build input pathname changed during fingerprinting: {path.name}") from error
        if (
            stat.S_ISLNK(current_path.st_mode)
            or not stat.S_ISREG(current_path.st_mode)
            or _stat_identity(current_path) != _stat_identity(after)
        ):
            raise ProvenanceError(f"private build input pathname changed during fingerprinting: {path.name}")
        return after, digest.hexdigest()
'''
new = '''        try:
            current_path = path.lstat()
            final_descriptor = os.fstat(descriptor)
        except OSError as error:
            raise ProvenanceError(f"private build input pathname changed during fingerprinting: {path.name}") from error
        if (
            stat.S_ISLNK(current_path.st_mode)
            or not stat.S_ISREG(current_path.st_mode)
            or _stat_identity(current_path) != _stat_identity(after)
            or _stat_identity(final_descriptor) != _stat_identity(after)
        ):
            raise ProvenanceError(f"private build input changed during final fingerprint custody: {path.name}")
        return final_descriptor, digest.hexdigest()
'''
if source.count(old) != 1:
    raise SystemExit(f"post-path final-descriptor seam drifted: {source.count(old)}")
helper_path.write_text(source.replace(old, new, 1), encoding="utf-8")

test_path = Path("scripts/ci/tests/test_capture_tuya_private_input_provenance.py")
tests = test_path.read_text(encoding="utf-8")
anchor = '''    def test_tree_rejects_file_replacement_after_individual_fingerprint(self) -> None:
'''
insert = '''    def test_file_fingerprint_rejects_same_inode_mutation_after_pathname_sample(self) -> None:
        target = self.security_podspec
        size = target.stat().st_size
        inode = target.stat().st_ino
        original_lstat = Path.lstat
        mutated = False

        def lstat_then_mutate(path: Path) -> os.stat_result:
            nonlocal mutated
            metadata = original_lstat(path)
            if path == target and not mutated:
                mutated = True
                target.write_bytes(b"R" * size)
                os.utime(
                    target,
                    ns=(metadata.st_atime_ns, metadata.st_mtime_ns + 1_000_000_000),
                )
            return metadata

        with mock.patch.object(Path, "lstat", autospec=True, side_effect=lstat_then_mutate):
            with self.assertRaises(provenance.ProvenanceError):
                provenance._file_fingerprint(target)

        self.assertTrue(mutated)
        self.assertEqual(target.stat().st_ino, inode)
        self.assertEqual(target.stat().st_size, size)

'''
if tests.count(anchor) != 1:
    raise SystemExit(f"post-path test insertion seam drifted: {tests.count(anchor)}")
test_path.write_text(tests.replace(anchor, insert + anchor, 1), encoding="utf-8")

updated = helper_path.read_text(encoding="utf-8")
block = updated.split("def _read_stable_regular_file_sha256", 1)[1].split("def _file_fingerprint", 1)[0]
for token in [
    "final_descriptor = os.fstat(descriptor)",
    "_stat_identity(final_descriptor) != _stat_identity(after)",
    "return final_descriptor, digest.hexdigest()",
]:
    if token not in block:
        raise SystemExit(f"post-path final identity contract missing: {token}")
