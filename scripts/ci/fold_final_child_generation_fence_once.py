#!/usr/bin/env python3
from pathlib import Path

HELPER = Path("scripts/ci/capture_accepted_build_input_snapshot.py")
TEST = Path("scripts/ci/tests/test_capture_generated_shared_ancestor_continuity.py")

old = '''            child = _open_directory_at(current, component, relative)\n            held: int | None = None\n            try:\n                if not is_last and directory_cache is not None:\n                    held = os.dup(child)\n                    admitted = os.fstat(held)\n                    directory_cache[relative] = (held, admitted)\n                    held = None\n            except Exception:\n                if held is not None:\n                    try:\n                        os.close(held)\n                    except OSError:\n                        pass\n                os.close(child)\n                raise\n            os.close(current)\n            current = child\n'''
new = '''            child = _open_directory_at(current, component, relative)\n            held: int | None = None\n            try:\n                if directory_cache is not None and index > 0:\n                    parent_relative = Path(*subject.parts[:index])\n                    cached_parent = directory_cache.get(parent_relative)\n                    if cached_parent is not None:\n                        _cached_descriptor, parent_admitted = cached_parent\n                        _assert_directory_generation(current, parent_admitted, parent_relative)\n                if not is_last and directory_cache is not None:\n                    held = os.dup(child)\n                    admitted = os.fstat(held)\n                    directory_cache[relative] = (held, admitted)\n                    held = None\n            except Exception:\n                if held is not None:\n                    try:\n                        os.close(held)\n                    except OSError:\n                        pass\n                try:\n                    os.close(child)\n                except OSError:\n                    pass\n                raise\n            os.close(current)\n            current = child\n'''

source = HELPER.read_text(encoding="utf-8")
if source.count(old) != 1:
    raise SystemExit("expected exactly one final-child admission seam")
HELPER.write_text(source.replace(old, new), encoding="utf-8")

marker = '\n\nif __name__ == "__main__":\n    unittest.main(verbosity=2)\n'
regression = r'''

    def test_manifest_rejects_or_holds_final_child_swap_after_parent_revalidation(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-final-child-manifest-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
            generation_a.rename(root / "LocalSecrets")
            pure_a = helper.canonical_generated_manifest(root, SOURCE_SHA)
            original_open = helper._open_directory_at
            swapped = False

            def splice_after_parent_check(parent_fd: int, name: str, relative: Path):
                nonlocal swapped
                if relative == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    active = root / "LocalSecrets"
                    (active / "TuyaRuntime").rename(active / "TuyaRuntime.A.attack")
                    (generation_b / "TuyaRuntime").rename(active / "TuyaRuntime")
                    swapped = True
                return original_open(parent_fd, name, relative)

            try:
                with mock.patch.object(helper, "_open_directory_at", side_effect=splice_after_parent_check):
                    attacked = helper.canonical_generated_manifest(root, SOURCE_SHA)
            except helper.AcceptedBuildInputSnapshotError:
                self.assertTrue(swapped)
                return

            self.assertTrue(swapped)
            self.assertEqual(attacked, pure_a)

    def test_copy_rejects_or_holds_final_child_swap_after_parent_revalidation(self) -> None:
        helper = load()
        with tempfile.TemporaryDirectory(prefix="nembra-final-child-copy-") as raw:
            root = Path(raw)
            seed_common(root)
            generation_a = make_generation(root, "LocalSecrets.A", b"SDK-A\n", b"RUNTIME-A\n")
            generation_b = make_generation(root, "LocalSecrets.B", b"SDK-B\n", b"RUNTIME-B\n")
            generation_a.rename(root / "LocalSecrets")
            destination = root / "stage"
            destination.mkdir()
            original_open = helper._open_directory_at
            swapped = False

            def splice_after_parent_check(parent_fd: int, name: str, relative: Path):
                nonlocal swapped
                if relative == Path("LocalSecrets/TuyaRuntime") and not swapped:
                    active = root / "LocalSecrets"
                    (active / "TuyaRuntime").rename(active / "TuyaRuntime.A.attack")
                    (generation_b / "TuyaRuntime").rename(active / "TuyaRuntime")
                    swapped = True
                return original_open(parent_fd, name, relative)

            try:
                with mock.patch.object(helper, "_open_directory_at", side_effect=splice_after_parent_check):
                    helper._copy_generated_subjects(root, destination)
            except helper.AcceptedBuildInputSnapshotError:
                self.assertTrue(swapped)
                return

            self.assertTrue(swapped)
            self.assertEqual((destination / "LocalSecrets/TuyaSDK/sdk.bin").read_bytes(), b"SDK-A\n")
            self.assertEqual(
                (destination / "LocalSecrets/TuyaRuntime/identity.bin").read_bytes(),
                b"RUNTIME-A\n",
            )
'''

source = TEST.read_text(encoding="utf-8")
if source.count(marker) != 1:
    raise SystemExit("unexpected continuity test footer")
if "test_manifest_rejects_or_holds_final_child_swap_after_parent_revalidation" in source:
    raise SystemExit("final-child generation fence regression already present")
TEST.write_text(source.replace(marker, regression + marker), encoding="utf-8")
