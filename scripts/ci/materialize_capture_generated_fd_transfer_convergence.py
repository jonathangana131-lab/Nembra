#!/usr/bin/env python3
"""One-shot author for the serial generated-input FD-ownership convergence."""
from __future__ import annotations

from pathlib import Path

HELPER = Path("scripts/ci/capture_accepted_build_input_snapshot.py")
TEST = Path("scripts/ci/tests/test_capture_generated_shared_ancestor_continuity.py")
WORKFLOW = Path(".github/workflows/capture-generated-shared-ancestor-continuity.yml")


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label} cardinality mismatch: expected 1, got {count}")
    return source.replace(old, new, 1)


def main() -> None:
    helper = HELPER.read_text(encoding="utf-8")
    old = """                cached_descriptor, admitted = directory_cache[relative]\n                _assert_directory_generation(cached_descriptor, admitted, relative)\n                selection_ancestors.append((cached_descriptor, admitted, relative))\n                os.close(current)\n                current = os.dup(cached_descriptor)\n                continue\n"""
    new = """                cached_descriptor, admitted = directory_cache[relative]\n                _assert_directory_generation(cached_descriptor, admitted, relative)\n                replacement = os.dup(cached_descriptor)\n                selection_ancestors.append((cached_descriptor, admitted, relative))\n                previous = current\n                current = replacement\n                os.close(previous)\n                continue\n"""
    HELPER.write_text(replace_once(helper, old, new, "cached-parent transfer seam"), encoding="utf-8")

    tests = TEST.read_text(encoding="utf-8")
    marker = '\n\nif __name__ == "__main__":\n    unittest.main(verbosity=2)\n'
    addition = r'''

    def test_cached_reuse_dup_failure_does_not_close_reused_fd_number(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-cached-reuse-dup-cleanup-") as raw:
            root = Path(raw)
            (root / "LocalSecrets/TuyaSDK").mkdir(parents=True)
            (root / "LocalSecrets/TuyaRuntime").mkdir(parents=True)
            sentinel_path = root / "sentinel.bin"
            sentinel_path.write_bytes(b"sentinel\n")
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
    TEST.write_text(replace_once(tests, marker, addition + marker, "test insertion marker"), encoding="utf-8")

    workflow = WORKFLOW.read_text(encoding="utf-8")
    if "Capture Generated FD Transfer Convergence Author" not in workflow:
        raise SystemExit("unexpected author workflow identity")


if __name__ == "__main__":
    main()
