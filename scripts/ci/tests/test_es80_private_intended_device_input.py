import importlib.util
import os
import pathlib
import stat
import tempfile
import unittest

MODULE_PATH = pathlib.Path(__file__).parents[1] / "es80_private_intended_device_input.py"
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
        with self.assertRaises(private_input.PrivateInputError):
            private_input._validate_identifier(" ABC123")
        with self.assertRaises(private_input.PrivateInputError):
            private_input._validate_identifier("ABC123\n")


if __name__ == "__main__":
    unittest.main()
