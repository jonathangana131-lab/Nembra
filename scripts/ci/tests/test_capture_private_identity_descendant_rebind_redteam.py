#!/usr/bin/env python3
"""Expected-red regression for private identity descendant-name rebinding.

This diagnostic targets the exact #2755 publication model: the writer holds
admitted descendant directory descriptors, but the final root-relative rename
and reopen re-resolve the canonical descendant names. A same-UID replacement
hierarchy can therefore receive the sealed credential-bearing staging inode
before the later held-chain reproof rejects the overall provision.

The invariant is fail-closed: a rejected provision must not leave credential
identity bytes in a replacement descendant tree.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
WRITER_PATH = REPOSITORY / "Scripts" / "provision_capture_tuya_identity_writer.py"


def load_writer():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_identity_descendant_rebind_redteam",
        WRITER_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PrivateIdentityDescendantRebindTests(unittest.TestCase):
    def test_replacement_descendant_cannot_retain_credentials_after_rejection(self) -> None:
        writer = load_writer()
        key_b64 = "bmVtYnJhLWR1bW15LWFwcC1rZXk="
        secret_b64 = "bmVtYnJhLWR1bW15LWFwcC1zZWNyZXQ="

        with tempfile.TemporaryDirectory(prefix="nembra-private-descendant-rebind-") as temporary:
            checkout = Path(temporary) / "repo"
            checkout.mkdir(mode=0o700)
            checkout_fd = os.open(checkout, writer._directory_flags())

            original_publish = writer._secure_replace_beneath
            attacked = False
            displaced_runtime = checkout / "LocalSecrets" / "TuyaRuntime.admitted"

            def adversarial_publish(root_fd: int, src: str, dst: str) -> None:
                nonlocal attacked
                if not attacked and dst.endswith("NembraTuyaPrivateIdentity.swift"):
                    admitted_runtime = checkout / "LocalSecrets" / "TuyaRuntime"
                    self.assertTrue(admitted_runtime.is_dir())
                    admitted_runtime.rename(displaced_runtime)

                    replacement_module = (
                        checkout
                        / "LocalSecrets"
                        / "TuyaRuntime"
                        / "Sources"
                        / "NembraTuyaPrivateConfig"
                    )
                    replacement_module.mkdir(parents=True, mode=0o700)
                    attacked = True

                original_publish(root_fd, src, dst)

            writer._secure_replace_beneath = adversarial_publish
            rejected = False
            try:
                try:
                    writer.provision(checkout_fd, checkout, key_b64, secret_b64)
                except (writer.ProvisionError, OSError):
                    rejected = True
            finally:
                writer._secure_replace_beneath = original_publish
                os.close(checkout_fd)

            replacement_identity = (
                checkout
                / "LocalSecrets"
                / "TuyaRuntime"
                / "Sources"
                / "NembraTuyaPrivateConfig"
                / "NembraTuyaPrivateIdentity.swift"
            )
            leaked_bytes = replacement_identity.read_bytes() if replacement_identity.exists() else None

            self.assertTrue(attacked, "diagnostic never reached credential-bearing publication")
            self.assertTrue(
                rejected,
                "writer accepted a provision after canonical descendant ancestry was rebound",
            )
            self.assertIsNone(
                leaked_bytes,
                "rejected provision left credential-bearing identity bytes in the replacement descendant tree",
            )

            # The attack is intentionally about publication to the replacement
            # hierarchy, not pre-existing credential bytes in the displaced
            # admitted tree.
            displaced_identity = (
                displaced_runtime
                / "Sources"
                / "NembraTuyaPrivateConfig"
                / "NembraTuyaPrivateIdentity.swift"
            )
            self.assertFalse(
                displaced_identity.exists(),
                "credential identity unexpectedly existed in admitted descendants before the attack seam",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
