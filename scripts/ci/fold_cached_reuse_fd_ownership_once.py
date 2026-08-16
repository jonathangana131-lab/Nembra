#!/usr/bin/env python3
from pathlib import Path

helper = Path("scripts/ci/capture_accepted_build_input_snapshot.py")
text = helper.read_text(encoding="utf-8")
old = '''            if not is_last and directory_cache is not None and relative in directory_cache:
                cached_descriptor, admitted = directory_cache[relative]
                _assert_directory_generation(cached_descriptor, admitted, relative)
                selection_ancestors.append((cached_descriptor, admitted, relative))
                os.close(current)
                current = os.dup(cached_descriptor)
                continue
'''
new = '''            if not is_last and directory_cache is not None and relative in directory_cache:
                cached_descriptor, admitted = directory_cache[relative]
                _assert_directory_generation(cached_descriptor, admitted, relative)
                selection_ancestors.append((cached_descriptor, admitted, relative))
                replacement = os.dup(cached_descriptor)
                previous = current
                current = replacement
                os.close(previous)
                continue
'''
if text.count(old) != 1:
    raise SystemExit("cached-reuse ownership seam did not match exactly once")
helper.write_text(text.replace(old, new), encoding="utf-8")

test = Path("scripts/ci/tests/test_capture_generated_shared_ancestor_continuity.py")
text = test.read_text(encoding="utf-8")
marker = '''\n    def test_cache_dup_failure_closes_newly_opened_child_descriptor(self) -> None:\n'''
regression = '''
    def test_cached_reuse_dup_failure_does_not_close_reused_fd_number(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-cached-reuse-dup-cleanup-") as raw:
            root = Path(raw)
            (root / "LocalSecrets/TuyaSDK").mkdir(parents=True)
            (root / "LocalSecrets/TuyaRuntime").mkdir(parents=True)
            sentinel_path = root / "sentinel.bin"
            sentinel_path.write_bytes(b"sentinel\\n")
            root_fd = helper._open_repository_root(root)
            cache: dict[Path, tuple[int, os.stat_result]] = {}
            opened, _metadata, _kind = helper._open_subject(
                root_fd,
                Path("LocalSecrets/TuyaSDK"),
                cache,
            )
            os.close(opened)
            cached_descriptor = cache[Path("LocalSecrets")][0]
            real_dup = os.dup
            sentinel_fd: int | None = None

            def fail_cached_reuse(descriptor: int) -> int:
                nonlocal sentinel_fd
                if descriptor == cached_descriptor:
                    sentinel_fd = os.open(sentinel_path, os.O_RDONLY)
                    raise OSError(errno.EMFILE, "synthetic cached-reuse dup exhaustion")
                return real_dup(descriptor)

            try:
                with mock.patch.object(helper.os, "dup", side_effect=fail_cached_reuse):
                    with self.assertRaisesRegex(OSError, "synthetic cached-reuse dup exhaustion"):
                        helper._open_subject(
                            root_fd,
                            Path("LocalSecrets/TuyaRuntime"),
                            cache,
                        )
                self.assertIsNotNone(sentinel_fd)
                assert sentinel_fd is not None
                os.fstat(sentinel_fd)
                os.fstat(cached_descriptor)
            finally:
                if sentinel_fd is not None:
                    try:
                        os.close(sentinel_fd)
                    except OSError:
                        pass
                helper._close_directory_cache(cache)
                os.close(root_fd)

'''
if text.count(marker) != 1:
    raise SystemExit("cached-reuse regression marker did not match exactly once")
test.write_text(text.replace(marker, "\n" + regression + marker.lstrip("\n")), encoding="utf-8")
