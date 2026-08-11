import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

CI_ROOT = Path(__file__).resolve().parents[1]
GO_PATH = CI_ROOT / "es80_authenticated_stationary_final_go.py"
SIGNED_PATH = CI_ROOT / "es80_authenticated_stationary_signed_artifact.py"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


go = load("final_go", GO_PATH)
signed = load("signed_artifact", SIGNED_PATH)


class FinalGoDeviceAncestorSwapTests(unittest.TestCase):
    def test_final_go_rejects_ancestor_retarget_between_path_admission_and_open(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            admitted = root / "private"
            admitted.mkdir()
            device = admitted / "device"
            device.write_text("device-A\n")
            device.chmod(0o600)

            replacement = root / "replacement"
            replacement.mkdir()
            replacement_device = replacement / "device"
            replacement_device.write_text("device-B\n")
            replacement_device.chmod(0o600)

            original = go.canonical_private_path
            moved = root / "private-admitted-original"

            def admit_then_retarget(path, label):
                result = original(path, label)
                os.rename(admitted, moved)
                os.rename(replacement, admitted)
                return result

            go.canonical_private_path = admit_then_retarget
            try:
                with self.assertRaises(go.GoError):
                    go.device_hash(device)
            finally:
                go.canonical_private_path = original

    def test_signed_artifact_reader_rejects_symlinked_ancestor(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo = root / "repo"
            repo.mkdir()
            private = root / "private"
            private.mkdir()
            device = private / "device"
            device.write_text("device-A\n")
            device.chmod(0o600)
            alias = root / "alias"
            alias.symlink_to(private, target_is_directory=True)

            with self.assertRaises(signed.SignedArtifactError):
                signed._read_intended_device(alias / "device", repo)


if __name__ == "__main__":
    unittest.main(verbosity=2)
