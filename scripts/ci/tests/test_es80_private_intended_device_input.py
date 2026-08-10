import contextlib
import importlib.util
import io
import os
import pathlib
import stat
import tempfile
import unittest
import warnings

MODULE_PATH = pathlib.Path(__file__).parents[1] / "es80_private_intended_device_input.py"
REPOSITORY_ROOT = pathlib.Path(__file__).parents[3]
HANDOFF_PATH = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"
spec = importlib.util.spec_from_file_location("private_input", MODULE_PATH)
private_input = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(private_input)


class PrivateInputTests(unittest.TestCase):
    def private_dir(self, root: pathlib.Path, name: str = "private") -> pathlib.Path:
        path = root / name
        path.mkdir(mode=0o700)
        os.chmod(path, 0o700)
        return path

    def test_creates_exact_bytes_mode_0600_and_single_link(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            private_dir = self.private_dir(root)
            output = private_dir / "device.udid"
            private_input.create_private_input(str(output), "00008101ABCDEF0123456789")
            self.assertEqual(output.read_bytes(), b"00008101ABCDEF0123456789")
            info = output.stat()
            self.assertEqual(stat.S_IMODE(info.st_mode), 0o600)
            self.assertEqual(info.st_nlink, 1)

    def test_refuses_existing_destination_without_clobbering(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            private_dir = self.private_dir(root)
            output = private_dir / "device.udid"
            output.write_bytes(b"preserve")
            os.chmod(output, 0o600)
            with self.assertRaises(FileExistsError):
                private_input.create_private_input(str(output), "NEWVALUE")
            self.assertEqual(output.read_bytes(), b"preserve")

    def test_refuses_symlinked_parent_component(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            real_dir = self.private_dir(root, "real")
            link = root / "link"
            link.symlink_to(real_dir, target_is_directory=True)
            output = link / "device.udid"
            with self.assertRaises(OSError):
                private_input.create_private_input(str(output), "ABC123")
            self.assertFalse((real_dir / "device.udid").exists())

    def test_parent_path_retarget_after_descriptor_open_cannot_redirect_write(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            trusted = self.private_dir(root, "trusted")
            attacker = self.private_dir(root, "attacker")
            output = trusted / "device.udid"

            parent_fd, filename = private_input._open_parent_directory(str(output))
            moved = root / "trusted-original"
            trusted.rename(moved)
            (root / "trusted").symlink_to(attacker, target_is_directory=True)
            try:
                fd = os.open(filename, private_input._file_flags(), 0o600, dir_fd=parent_fd)
                try:
                    os.write(fd, b"ABC123")
                    os.fsync(fd)
                finally:
                    os.close(fd)
            finally:
                os.close(parent_fd)

            self.assertEqual((moved / "device.udid").read_bytes(), b"ABC123")
            self.assertFalse((attacker / "device.udid").exists())

    def test_refuses_group_or_world_accessible_parent(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            private_dir = root / "private"
            private_dir.mkdir(mode=0o755)
            os.chmod(private_dir, 0o755)
            with self.assertRaises(private_input.PrivateInputError):
                private_input.create_private_input(str(private_dir / "device.udid"), "ABC123")

    def test_rejects_whitespace_and_control_characters(self):
        for value in (" ABC123", "ABC 123", "ABC\t123", "ABC123\n"):
            with self.subTest(value=repr(value)):
                with self.assertRaises(private_input.PrivateInputError):
                    private_input._validate_identifier(value)

    def test_secure_input_warning_fails_closed_before_fallback_value_is_consumed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            private_dir = self.private_dir(root)
            output = private_dir / "device.udid"
            fallback_returned = False
            original_getpass = private_input.getpass.getpass

            def insecure_fallback(_prompt: str) -> str:
                nonlocal fallback_returned
                warnings.warn(
                    "Can not control echo on the terminal.",
                    private_input.getpass.GetPassWarning,
                )
                fallback_returned = True
                return "SHOULD_NOT_BE_CONSUMED"

            private_input.getpass.getpass = insecure_fallback
            stdout = io.StringIO()
            stderr = io.StringIO()
            try:
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    exit_code = private_input.main(["--output-path", str(output)])
            finally:
                private_input.getpass.getpass = original_getpass

            self.assertEqual(exit_code, 2)
            self.assertFalse(fallback_returned)
            self.assertFalse(output.exists())
            self.assertNotIn("SHOULD_NOT_BE_CONSUMED", stdout.getvalue())
            self.assertNotIn("SHOULD_NOT_BE_CONSUMED", stderr.getvalue())
            self.assertIn("secure terminal input unavailable", stderr.getvalue())

    def test_operator_handoff_uses_pinned_descriptor_bound_helper_not_shell_secret_redirection(self):
        handoff = HANDOFF_PATH.read_text(encoding="utf-8")
        self.assertIn("scripts/ci/es80_private_intended_device_input.py", handoff)
        self.assertIn("PRIVATE_INPUT_HELPER_COMMIT=", handoff)
        self.assertIn("PRIVATE_INPUT_HELPER_BLOB=", handoff)
        self.assertIn('/usr/bin/python3 -I "$PRIVATE_INPUT_HELPER" --output-path "$UDID_FILE"', handoff)
        self.assertNotIn("IFS= read -r -s INTENDED_UDID", handoff)
        self.assertNotIn("set -o noclobber", handoff)
        self.assertNotIn("printf '%s' \"$INTENDED_UDID\" > \"$UDID_FILE\"", handoff)


if __name__ == "__main__":
    unittest.main()
