from pathlib import Path

helper = Path("Scripts/capture_tuya_private_input_provenance.py")
source = helper.read_text(encoding="utf-8")
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
    raise SystemExit(f"post-path descriptor seam drifted: {source.count(old)}")
helper.write_text(source.replace(old, new, 1), encoding="utf-8")

test = Path("scripts/ci/tests/test_capture_tuya_private_input_post_path_descriptor_custody.py")
test.write_text('''#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock
ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "Scripts" / "capture_tuya_private_input_provenance.py"
SPEC = importlib.util.spec_from_file_location("capture_tuya_private_input_provenance", HELPER)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load provenance helper")
provenance = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(provenance)
class PostPathDescriptorCustodyTests(unittest.TestCase):
    def test_same_inode_mutation_after_pathname_sample_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "input.podspec"
            target.write_bytes(b"AAAA")
            inode = target.stat().st_ino
            original_lstat = Path.lstat
            changed = False
            def lstat_then_change(path: Path) -> os.stat_result:
                nonlocal changed
                metadata = original_lstat(path)
                if path == target and not changed:
                    changed = True
                    target.write_bytes(b"BBBB")
                    os.utime(target, ns=(metadata.st_atime_ns, metadata.st_mtime_ns + 1_000_000_000))
                return metadata
            with mock.patch.object(Path, "lstat", autospec=True, side_effect=lstat_then_change):
                with self.assertRaises(provenance.ProvenanceError):
                    provenance._file_fingerprint(target)
            self.assertTrue(changed)
            self.assertEqual(target.stat().st_ino, inode)
            self.assertEqual(target.stat().st_size, 4)
if __name__ == "__main__":
    unittest.main()
''', encoding="utf-8")
