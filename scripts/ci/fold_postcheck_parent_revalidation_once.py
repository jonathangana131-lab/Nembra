#!/usr/bin/env python3
from pathlib import Path

helper = Path("scripts/ci/capture_accepted_build_input_snapshot.py")
text = helper.read_text(encoding="utf-8")

old = '''            if not is_last and directory_cache is not None and relative in directory_cache:
                cached_descriptor, admitted = directory_cache[relative]
                _assert_directory_generation(cached_descriptor, admitted, relative)
                os.close(current)
                current = os.dup(cached_descriptor)
                continue
'''
new = '''            if not is_last and directory_cache is not None and relative in directory_cache:
                cached_descriptor, admitted = directory_cache[relative]
                _assert_directory_generation(cached_descriptor, admitted, relative)
                replacement = os.dup(cached_descriptor)
                previous = current
                current = replacement
                os.close(previous)
                continue
'''
if text.count(old) != 1:
    raise SystemExit("cached-ancestor reuse seam did not match exactly once")
text = text.replace(old, new)

old = '''            if is_last and expected_kind == "file":
                descriptor, metadata = _open_file_at(current, component, relative)
                os.close(current)
                return descriptor, metadata, "file"
'''
new = '''            if is_last and expected_kind == "file":
                descriptor, metadata = _open_file_at(current, component, relative)
                try:
                    if directory_cache is not None:
                        for cached_relative, (cached_descriptor, admitted) in directory_cache.items():
                            _assert_directory_generation(
                                cached_descriptor,
                                admitted,
                                cached_relative,
                            )
                except Exception:
                    os.close(descriptor)
                    raise
                os.close(current)
                return descriptor, metadata, "file"
'''
if text.count(old) != 1:
    raise SystemExit("final-file postcheck seam did not match exactly once")
text = text.replace(old, new)

old = '''        metadata = os.fstat(current)
        return current, metadata, "directory"
'''
new = '''        metadata = os.fstat(current)
        if directory_cache is not None:
            for cached_relative, (cached_descriptor, admitted) in directory_cache.items():
                _assert_directory_generation(
                    cached_descriptor,
                    admitted,
                    cached_relative,
                )
        return current, metadata, "directory"
'''
if text.count(old) != 1:
    raise SystemExit("final-directory postcheck seam did not match exactly once")
text = text.replace(old, new)
helper.write_text(text, encoding="utf-8")

test = Path("scripts/ci/tests/test_capture_generated_shared_ancestor_continuity.py")
text = test.read_text(encoding="utf-8")
marker = '''\n\n    def test_cache_dup_failure_closes_newly_opened_child_descriptor(self) -> None:
'''
regressions = '''

    def test_manifest_rejects_postcheck_runtime_sibling_splice(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-postcheck-splice-manifest-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\\n", b"RUNTIME-A\\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\\n", b"RUNTIME-B\\n")
            generation_a.rename(root / "LocalSecrets")
            pure_a = helper.canonical_generated_manifest(root, SOURCE_SHA)
            original_open_directory = helper._open_directory_at
            swapped = False

            def splice_after_parent_precheck(parent_fd: int, name: str, relative: Path) -> int:
                nonlocal swapped
                if relative == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    active = root / "LocalSecrets"
                    (active / "TuyaRuntime").rename(active / "TuyaRuntime.A.attack")
                    (generation_b / "TuyaRuntime").rename(active / "TuyaRuntime")
                    swapped = True
                return original_open_directory(parent_fd, name, relative)

            try:
                with mock.patch.object(helper, "_open_directory_at", side_effect=splice_after_parent_precheck):
                    held = helper.canonical_generated_manifest(root, SOURCE_SHA)
            except helper.AcceptedBuildInputSnapshotError:
                self.assertTrue(swapped)
                return

            self.assertTrue(swapped)
            self.assertEqual(held, pure_a)
            payload = json.loads(held)
            self.assertEqual(
                entry_sha(payload, "LocalSecrets/TuyaSDK/sdk.bin"),
                hashlib.sha256(b"SDK-A\\n").hexdigest(),
            )
            self.assertEqual(
                entry_sha(payload, "LocalSecrets/TuyaRuntime/identity.bin"),
                hashlib.sha256(b"RUNTIME-A\\n").hexdigest(),
            )

    def test_copy_rejects_postcheck_runtime_sibling_splice(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-postcheck-splice-copy-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\\n", b"RUNTIME-A\\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\\n", b"RUNTIME-B\\n")
            generation_a.rename(root / "LocalSecrets")
            destination = root / "stage"
            destination.mkdir()
            original_open_directory = helper._open_directory_at
            swapped = False

            def splice_after_parent_precheck(parent_fd: int, name: str, relative: Path) -> int:
                nonlocal swapped
                if relative == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    active = root / "LocalSecrets"
                    (active / "TuyaRuntime").rename(active / "TuyaRuntime.A.attack")
                    (generation_b / "TuyaRuntime").rename(active / "TuyaRuntime")
                    swapped = True
                return original_open_directory(parent_fd, name, relative)

            try:
                with mock.patch.object(helper, "_open_directory_at", side_effect=splice_after_parent_precheck):
                    helper._copy_generated_subjects(root, destination)
            except helper.AcceptedBuildInputSnapshotError:
                self.assertTrue(swapped)
                return

            self.assertTrue(swapped)
            self.assertEqual((destination / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(), b"SDK-A\\n")
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/identity.bin").read_bytes(),
                b"RUNTIME-A\\n",
            )

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
    raise SystemExit("continuity regression insertion marker did not match exactly once")
text = text.replace(marker, regressions + marker)
test.write_text(text, encoding="utf-8")
