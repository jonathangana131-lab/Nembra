#!/usr/bin/env python3
from pathlib import Path

helper = Path("scripts/ci/capture_accepted_build_input_snapshot.py")
text = helper.read_text(encoding="utf-8")

old = '''    current = os.dup(root_fd)
    try:
        for index, component in enumerate(subject.parts):
'''
new = '''    current = os.dup(root_fd)
    selection_ancestors: list[tuple[int, os.stat_result, Path]] = []

    def revalidate_selection_ancestors() -> None:
        for descriptor, admitted, relative in selection_ancestors:
            _assert_directory_generation(descriptor, admitted, relative)

    try:
        for index, component in enumerate(subject.parts):
'''
if text.count(old) != 1:
    raise SystemExit("helper selection-ancestor setup seam did not match exactly once")
text = text.replace(old, new)

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
                selection_ancestors.append((cached_descriptor, admitted, relative))
                os.close(current)
                current = os.dup(cached_descriptor)
                continue
'''
if text.count(old) != 1:
    raise SystemExit("helper cached-ancestor seam did not match exactly once")
text = text.replace(old, new)

old = '''            if is_last and expected_kind == "file":
                descriptor, metadata = _open_file_at(current, component, relative)
                os.close(current)
                return descriptor, metadata, "file"
'''
new = '''            if is_last and expected_kind == "file":
                descriptor, metadata = _open_file_at(current, component, relative)
                try:
                    revalidate_selection_ancestors()
                except Exception:
                    os.close(descriptor)
                    raise
                os.close(current)
                return descriptor, metadata, "file"
'''
if text.count(old) != 1:
    raise SystemExit("helper final-file seam did not match exactly once")
text = text.replace(old, new)

old = '''                    admitted = os.fstat(held)
                    directory_cache[relative] = (held, admitted)
                    held = None
'''
new = '''                    admitted = os.fstat(held)
                    directory_cache[relative] = (held, admitted)
                    selection_ancestors.append((held, admitted, relative))
                    held = None
'''
if text.count(old) != 1:
    raise SystemExit("helper newly-cached-ancestor seam did not match exactly once")
text = text.replace(old, new)

old = '''            except Exception:
                if held is not None:
                    try:
                        os.close(held)
                    except OSError:
                        pass
                os.close(child)
                raise
            os.close(current)
            current = child
        metadata = os.fstat(current)
'''
new = '''            except Exception:
                if held is not None:
                    try:
                        os.close(held)
                    except OSError:
                        pass
                os.close(child)
                raise
            if is_last:
                try:
                    revalidate_selection_ancestors()
                except Exception:
                    os.close(child)
                    raise
            os.close(current)
            current = child
        metadata = os.fstat(current)
'''
if text.count(old) != 1:
    raise SystemExit("helper final-directory seam did not match exactly once")
text = text.replace(old, new)
helper.write_text(text, encoding="utf-8")


test = Path("scripts/ci/tests/test_capture_generated_shared_ancestor_continuity.py")
text = test.read_text(encoding="utf-8")
marker = '''\n\n    def test_cache_dup_failure_closes_newly_opened_child_descriptor(self) -> None:\n'''
regressions = r'''

    def test_manifest_rejects_runtime_swap_after_cached_parent_revalidation(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-final-child-manifest-reject-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
            generation_a.rename(root / "LocalSecrets")
            original_open = helper._open_directory_at
            swapped = False

            def splice_after_parent_check(parent_fd: int, name: str, relative: Path) -> int:
                nonlocal swapped
                if relative == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    active = root / "LocalSecrets"
                    (active / "TuyaRuntime").rename(active / "TuyaRuntime.A.attack")
                    (generation_b / "TuyaRuntime").rename(active / "TuyaRuntime")
                    swapped = True
                return original_open(parent_fd, name, relative)

            with mock.patch.object(helper, "_open_directory_at", side_effect=splice_after_parent_check):
                with self.assertRaises(helper.AcceptedBuildInputSnapshotError):
                    helper.canonical_generated_manifest(root, SOURCE_SHA)
            self.assertTrue(swapped)

    def test_copy_rejects_runtime_swap_after_cached_parent_revalidation(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-final-child-copy-reject-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
            generation_a.rename(root / "LocalSecrets")
            destination = root / "stage"
            destination.mkdir()
            original_open = helper._open_directory_at
            swapped = False

            def splice_after_parent_check(parent_fd: int, name: str, relative: Path) -> int:
                nonlocal swapped
                if relative == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    active = root / "LocalSecrets"
                    (active / "TuyaRuntime").rename(active / "TuyaRuntime.A.attack")
                    (generation_b / "TuyaRuntime").rename(active / "TuyaRuntime")
                    swapped = True
                return original_open(parent_fd, name, relative)

            with mock.patch.object(helper, "_open_directory_at", side_effect=splice_after_parent_check):
                with self.assertRaises(helper.AcceptedBuildInputSnapshotError):
                    helper._copy_generated_subjects(root, destination)
            self.assertTrue(swapped)
            self.assertEqual(
                (destination / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(),
                b"SDK-A\n",
            )
            self.assertFalse(
                (destination / "LocalSecrets/TuyaRuntime/identity.bin").exists()
            )
'''
if text.count(marker) != 1:
    raise SystemExit("continuity regression insertion marker did not match exactly once")
text = text.replace(marker, regressions + marker)
test.write_text(text, encoding="utf-8")
