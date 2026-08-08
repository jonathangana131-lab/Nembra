#!/usr/bin/env python3
"""Regression for failure-atomic offline field-authorization publication."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
from unittest import mock


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SIGNER_PATH = REPOSITORY_ROOT / "scripts/ci/es80_field_authorization_envelope.py"

spec = importlib.util.spec_from_file_location("es80_field_authorization_envelope", SIGNER_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("could not load field authorization signer")
signer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signer)


def main() -> None:
    envelope = b'{"fixture":"signed-authorization-envelope"}\n'
    with tempfile.TemporaryDirectory(prefix="nembra-auth-envelope-atomic-test-") as temporary:
        directory = Path(temporary)
        output = directory / "NembraCaptureFieldAuthorizationEnvelope.json"

        with mock.patch.object(
            signer.os,
            "fsync",
            side_effect=OSError("simulated durability failure"),
        ):
            try:
                signer.write_envelope_no_replace(output, envelope)
            except signer.AuthorizationEnvelopeError as error:
                if "could not publish" not in str(error):
                    raise AssertionError(f"unexpected publication error: {error}") from error
            else:
                raise AssertionError("simulated durability failure unexpectedly published")

        if output.exists():
            raise AssertionError(
                "failed publication left the final authorization-envelope path occupied"
            )
        leftovers = list(directory.glob(".*authorization-envelope*.staging-*"))
        if leftovers:
            raise AssertionError(f"failed publication left staging artifacts: {leftovers}")

    print("field authorization atomic-publication regression: PASS")


if __name__ == "__main__":
    main()
