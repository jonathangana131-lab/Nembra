#!/usr/bin/env python3
"""Temporary V17 authoring helper. Self-deleted by the coherence materializer."""

from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


orchestrator = Path("scripts/ci/capture_selected_xcode_build_orchestrator.py")
text = orchestrator.read_text(encoding="utf-8")

marker = "def _darwin_acl_library():\n"
text = replace_once(
    text,
    marker,
    "_ACL_TYPE_EXTENDED = 0x00000100\n\n\n" + marker,
    "Darwin ACL library marker",
)

old = """    library.acl_get_fd.argtypes = [ctypes.c_int]\n    library.acl_get_fd.restype = ctypes.c_void_p\n"""
new = """    library.acl_get_fd.argtypes = [ctypes.c_int]\n    library.acl_get_fd.restype = ctypes.c_void_p\n    library.acl_get_file.argtypes = [ctypes.c_char_p, ctypes.c_int]\n    library.acl_get_file.restype = ctypes.c_void_p\n    library.acl_to_text.argtypes = [\n        ctypes.c_void_p,\n        ctypes.POINTER(ctypes.c_ssize_t),\n    ]\n    library.acl_to_text.restype = ctypes.c_void_p\n"""
text = replace_once(text, old, new, "Darwin ACL prototypes")

restore_marker = "\n\ndef _restore_fd_acl_baseline(descriptor: int, baseline_acl: int) -> None:\n"
helpers = r'''

def _native_acl_text(library, acl_handle: int, *, context: str) -> bytes:
    if acl_handle <= 0:
        raise SelectedXcodeBuildOrchestratorError(
            f"private read-lease native ACL is unavailable for {context}"
        )
    length = ctypes.c_ssize_t(0)
    ctypes.set_errno(0)
    text_pointer = library.acl_to_text(
        ctypes.c_void_p(acl_handle), ctypes.byref(length)
    )
    saved_errno = ctypes.get_errno()
    if not text_pointer:
        raise SelectedXcodeBuildOrchestratorError(
            f"could not canonicalize private read-lease native ACL for {context}"
            + (f": errno {saved_errno}" if saved_errno else "")
        )
    try:
        if length.value < 0:
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease native ACL text length is invalid for {context}"
            )
        return ctypes.string_at(text_pointer, length.value)
    finally:
        if library.acl_free(ctypes.c_void_p(text_pointer)) != 0:
            raise SelectedXcodeBuildOrchestratorError(
                f"could not free private read-lease native ACL text for {context}"
            )


def _free_native_acl_object(library, acl_handle: int, *, context: str) -> None:
    if acl_handle <= 0:
        return
    if library.acl_free(ctypes.c_void_p(acl_handle)) != 0:
        raise SelectedXcodeBuildOrchestratorError(
            f"could not free private read-lease native ACL object for {context}"
        )


def _require_native_acl_baseline_coherence(
    path: Path,
    descriptor: int,
    baseline_acl: int,
    accepted_signature: tuple[int, int, int],
    is_directory: bool,
) -> None:
    """Prove the retained fd rollback baseline equals canonical pre-grant truth."""
    _require_canonical_acl_identity(
        path, descriptor, accepted_signature, is_directory
    )
    library = _darwin_acl_library()
    ctypes.set_errno(0)
    path_acl = library.acl_get_file(os.fsencode(path), _ACL_TYPE_EXTENDED)
    path_errno = ctypes.get_errno()
    if path_acl:
        path_acl_handle = int(path_acl)
        try:
            baseline_text = _native_acl_text(
                library, baseline_acl, context=f"held descriptor baseline {path}"
            )
            path_text = _native_acl_text(
                library, path_acl_handle, context=f"canonical path baseline {path}"
            )
        finally:
            _free_native_acl_object(
                library, path_acl_handle, context=f"canonical path baseline {path}"
            )
        if baseline_text != path_text:
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease native ACL baseline does not match canonical path: {path}"
            )
    else:
        if path_errno != errno.ENOENT:
            raise SelectedXcodeBuildOrchestratorError(
                f"could not classify canonical private read-lease ACL baseline: {path}"
                + (f": errno {path_errno}" if path_errno else ": null result without errno")
            )
        ctypes.set_errno(0)
        descriptor_acl = library.acl_get_fd(descriptor)
        descriptor_errno = ctypes.get_errno()
        if descriptor_acl:
            descriptor_acl_handle = int(descriptor_acl)
            _free_native_acl_object(
                library,
                descriptor_acl_handle,
                context=f"descriptor absence cross-check {path}",
            )
            raise SelectedXcodeBuildOrchestratorError(
                f"private read-lease native ACL baseline does not match canonical path: {path}"
            )
        if descriptor_errno != errno.ENOENT:
            raise SelectedXcodeBuildOrchestratorError(
                f"could not classify descriptor private read-lease ACL baseline: {path}"
                + (
                    f": errno {descriptor_errno}"
                    if descriptor_errno
                    else ": null result without errno"
                )
            )
    _require_canonical_acl_identity(
        path, descriptor, accepted_signature, is_directory
    )
'''
text = replace_once(text, restore_marker, helpers + restore_marker, "native coherence helper insertion")

old = """                if self._use_native_darwin_acl:\n                    record[\"native_baseline_acl\"] = _capture_fd_acl_baseline(descriptor)\n                    before = _path_acl_listing(\n                        path, descriptor, accepted_signature, is_directory\n                    )\n"""
new = """                if self._use_native_darwin_acl:\n                    record[\"native_baseline_acl\"] = _capture_fd_acl_baseline(descriptor)\n                    _require_native_acl_baseline_coherence(\n                        path,\n                        descriptor,\n                        int(record[\"native_baseline_acl\"]),\n                        accepted_signature,\n                        is_directory,\n                    )\n                    before = _path_acl_listing(\n                        path, descriptor, accepted_signature, is_directory\n                    )\n"""
text = replace_once(text, old, new, "native coherence grant call")
orchestrator.write_text(text, encoding="utf-8")

witness = Path("scripts/ci/tests/test_capture_accepted_root_real_whole_read_lease.py")
test_text = witness.read_text(encoding="utf-8")

seed_marker = "def seed(root: Path):\n"
test_helpers = r'''def acl_listing(path: Path) -> str:
    completed = subprocess.run(
        ["/bin/ls", "-Hlde", str(path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr or "could not inspect ACL")
    return completed.stdout


def add_acl(path: Path, ace: str) -> None:
    completed = subprocess.run(
        ["/bin/chmod", "+a", ace, str(path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr or "could not seed ACL")


'''
test_text = replace_once(test_text, seed_marker, test_helpers + seed_marker, "real witness helper insertion")

old_tail = """        after = field_run(self.field, self.groups, probe, *targets)\n        self.assertNotEqual(after.returncode, 0)\n"""
new_tail = r'''        after = field_run(self.field, self.groups, probe, *targets)
        self.assertNotEqual(after.returncode, 0)

    def test_seeded_native_acl_baseline_is_restored_exactly(self):
        helper = load()
        root = self.outer / "accepted-seeded"
        root.mkdir(mode=0o700)
        seed(root)
        add_acl(root, "user:root allow readattr")
        baseline = acl_listing(root)
        target = root / "Podfile.lock"
        probe = "from pathlib import Path; import sys; Path(sys.argv[1]).read_bytes()"
        self.assertNotEqual(field_run(self.field, self.groups, probe, target).returncode, 0)

        lease = helper._PrivateReadLease((root,), root, use_native_darwin_acl=True)
        lease.grant(self.field.pw_name)
        try:
            during = field_run(self.field, self.groups, probe, target)
            self.assertEqual(during.returncode, 0, during.stderr)
        finally:
            lease.revoke()

        self.assertEqual(acl_listing(root), baseline)
        self.assertNotEqual(field_run(self.field, self.groups, probe, target).returncode, 0)

    def test_seeded_fd_path_baseline_mismatch_fails_before_authority(self):
        helper = load()
        root = self.outer / "accepted-mismatch"
        root.mkdir(mode=0o700)
        seed(root)
        add_acl(root, "user:root allow readattr")
        target = root / "Podfile.lock"
        probe = "from pathlib import Path; import sys; Path(sys.argv[1]).read_bytes()"
        original_capture = helper._capture_fd_acl_baseline
        mutated = False

        def capture_then_mutate(descriptor: int) -> int:
            nonlocal mutated
            baseline = original_capture(descriptor)
            if (
                not mutated
                and helper._descriptor_signature(descriptor)
                == helper._path_signature(root)
            ):
                add_acl(root, "group:wheel allow readattr")
                mutated = True
            return baseline

        helper._capture_fd_acl_baseline = capture_then_mutate
        lease = helper._PrivateReadLease((root,), root, use_native_darwin_acl=True)
        with self.assertRaisesRegex(
            helper.SelectedXcodeBuildOrchestratorError,
            "native ACL baseline does not match canonical path",
        ):
            lease.grant(self.field.pw_name)
        self.assertTrue(mutated)
        self.assertFalse(lease._opened)
        self.assertEqual(lease._principal, "")
        self.assertNotEqual(field_run(self.field, self.groups, probe, target).returncode, 0)
'''
test_text = replace_once(test_text, old_tail, new_tail, "real witness test insertion")
witness.write_text(test_text, encoding="utf-8")
