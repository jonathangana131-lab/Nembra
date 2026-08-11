#!/usr/bin/env python3
"""Expected-red source regression for private identity root/code custody ordering.

The checkout root that is authorized to receive credential-derived files must be
bound before any mutable pathname under that root is trusted as accepted writer
code. Otherwise a root replacement between writer capture and root admission can
join code from the original checkout to a destination identity from a replacement.
"""
from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PROVISIONER = ROOT / "Scripts/provision_capture_tuya_identity.sh"


class PrivateIdentityWriterRootOrderTests(unittest.TestCase):
    def test_checkout_root_is_bound_before_writer_path_is_trusted(self) -> None:
        source = PROVISIONER.read_text(encoding="utf-8")

        root_capture = source.find('ROOT_IDENTITY_CAPTURE="$(/usr/bin/python3 -I - "$ROOT"')
        root_validation = source.find('[[ "$ROOT_DEVICE" =~ ^[0-9]+$ && "$ROOT_INODE" =~ ^[0-9]+$ ]]')
        writer_capture = source.find('WRITER_CAPTURE="$({ /bin/cat -- "$WRITER";')
        writer_digest = source.find('[[ "$CAPTURED_WRITER_SHA256" == "$WRITER_SHA256" ]]')
        credential_read = source.find(
            'builtin read -r -s -p "Tuya SmartLife SDK AppKey (input hidden): " APP_KEY'
        )

        for label, offset in {
            "root identity capture": root_capture,
            "root identity validation": root_validation,
            "writer capture": writer_capture,
            "writer digest fence": writer_digest,
            "credential read": credential_read,
        }.items():
            self.assertNotEqual(offset, -1, f"missing {label} authority fence")

        # Required minimum ordering for the current design:
        # root identity -> accepted writer bytes -> secrets.
        # If a stronger descriptor handoff replaces these exact mechanisms, this
        # diagnostic should be superseded by an equivalent executable invariant.
        self.assertLess(
            root_validation,
            writer_capture,
            "checkout root must be fully admitted before the writer pathname is opened",
        )
        self.assertLess(writer_capture, writer_digest)
        self.assertLess(writer_digest, credential_read)

        # The publication handoff must still carry the already-admitted identity;
        # a later fresh pathname identity is not a substitute for this ordering.
        self.assertIn(
            '/usr/bin/python3 -I -c "$WRITER_SOURCE" "$ROOT" "$ROOT_DEVICE" "$ROOT_INODE"',
            source,
        )


if __name__ == "__main__":
    unittest.main()
