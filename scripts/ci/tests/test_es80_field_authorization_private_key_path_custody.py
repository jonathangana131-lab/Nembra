#!/usr/bin/env python3
import os
from pathlib import Path
import sys
import tempfile
import unittest

CI_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(CI_ROOT))

import es80_field_authorization_envelope as signer


class OfflineFieldAuthorizationPrivateKeyPathCustodyTests(unittest.TestCase):
    KEY_BYTES = b"nembra-private-key-path-custody-regression\n"

    def _write_key(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(self.KEY_BYTES)
        os.chmod(path, 0o600)

    def test_direct_owner_only_private_key_is_read(self):
        with tempfile.TemporaryDirectory(prefix="nembra-private-key-direct-") as name:
            key = Path(name) / "authority.pem"
            self._write_key(key)
            self.assertEqual(signer._read_private_key(key), self.KEY_BYTES)

    def test_final_private_key_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="nembra-private-key-final-link-") as name:
            root = Path(name)
            key = root / "real" / "authority.pem"
            self._write_key(key)
            linked = root / "authority.pem"
            linked.symlink_to(key)
            with self.assertRaises(signer.AuthorizationEnvelopeError):
                signer._read_private_key(linked)

    def test_private_key_symlinked_ancestor_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="nembra-private-key-ancestor-link-") as name:
            root = Path(name)
            real_directory = root / "real"
            key = real_directory / "authority.pem"
            self._write_key(key)
            linked_directory = root / "selected"
            linked_directory.symlink_to(real_directory, target_is_directory=True)
            with self.assertRaises(signer.AuthorizationEnvelopeError):
                signer._read_private_key(linked_directory / "authority.pem")

    def test_parent_traversal_component_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="nembra-private-key-dotdot-") as name:
            root = Path(name)
            key = root / "safe" / "authority.pem"
            self._write_key(key)
            suspicious = root / "safe" / ".." / "safe" / "authority.pem"
            with self.assertRaises(signer.AuthorizationEnvelopeError):
                signer._read_private_key(suspicious)


if __name__ == "__main__":
    unittest.main()
