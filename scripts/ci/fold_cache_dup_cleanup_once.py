#!/usr/bin/env python3
from pathlib import Path

helper = Path("scripts/ci/capture_accepted_build_input_snapshot.py")
text = helper.read_text(encoding="utf-8")
old = '''            child = _open_directory_at(current, component, relative)
            if not is_last and directory_cache is not None:
                held = os.dup(child)
                directory_cache[relative] = (held, os.fstat(held))
            os.close(current)
            current = child
'''
new = '''            child = _open_directory_at(current, component, relative)
            held: int | None = None
            try:
                if not is_last and directory_cache is not None:
                    held = os.dup(child)
                    admitted = os.fstat(held)
                    directory_cache[relative] = (held, admitted)
                    held = None
            except Exception:
                if held is not None:
                    try:
                        os.close(held)
                    except OSError:
                        pass
                os.close(child)
                raise
            os.close(current)
            current = child
'''
if text.count(old) != 1:
    raise SystemExit("helper cache-dup seam did not match exactly once")
helper.write_text(text.replace(old, new), encoding="utf-8")

test = Path("scripts/ci/tests/test_capture_generated_shared_ancestor_continuity.py")
text = test.read_text(encoding="utf-8")
old_imports = '''import hashlib
import importlib.util
import json
from pathlib import Path
'''
new_imports = '''import errno
import hashlib
import importlib.util
import json
import os
from pathlib import Path
'''
if text.count(old_imports) != 1:
    raise SystemExit("continuity-test imports did not match exactly once")
text = text.replace(old_imports, new_imports)
marker = '''\n\nif __name__ == "__main__":
    unittest.main(verbosity=2)
'''
regression = '''

    def test_cache_dup_failure_closes_newly_opened_child_descriptor(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-shared-ancestor-cache-dup-cleanup-") as raw:
            root = Path(raw)
            (root / "LocalSecrets/TuyaSDK").mkdir(parents=True)
            root_fd = helper._open_repository_root(root)
            real_dup = os.dup
            real_open_directory = helper._open_directory_at
            opened_children: list[int] = []
            dup_calls = 0

            def capture_open(parent_fd: int, name: str, relative: Path) -> int:
                descriptor = real_open_directory(parent_fd, name, relative)
                opened_children.append(descriptor)
                return descriptor

            def fail_cache_dup(descriptor: int) -> int:
                nonlocal dup_calls
                dup_calls += 1
                if dup_calls == 2:
                    raise OSError(errno.EMFILE, "synthetic cache-dup exhaustion")
                return real_dup(descriptor)

            cache: dict[Path, tuple[int, os.stat_result]] = {}
            try:
                with (
                    mock.patch.object(helper, "_open_directory_at", side_effect=capture_open),
                    mock.patch.object(helper.os, "dup", side_effect=fail_cache_dup),
                ):
                    with self.assertRaisesRegex(OSError, "synthetic cache-dup exhaustion"):
                        helper._open_subject(
                            root_fd,
                            Path("LocalSecrets/TuyaSDK"),
                            cache,
                        )

                self.assertEqual(dup_calls, 2)
                self.assertEqual(cache, {})
                self.assertEqual(len(opened_children), 1)
                with self.assertRaises(OSError):
                    os.fstat(opened_children[0])
            finally:
                for descriptor in opened_children:
                    try:
                        os.close(descriptor)
                    except OSError:
                        pass
                os.close(root_fd)
'''
if text.count(marker) != 1:
    raise SystemExit("continuity-test insertion marker did not match exactly once")
test.write_text(text.replace(marker, regression + marker), encoding="utf-8")
