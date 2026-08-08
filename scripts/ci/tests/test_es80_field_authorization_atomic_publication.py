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


def assert_no_staging(directory: Path) -> None:
    leftovers = list(directory.glob(".authorization-envelope-*.staging-*"))
    if leftovers:
        raise AssertionError(f"authorization publication left staging artifacts: {leftovers}")


def expect_publication_error(callable_, required_text: str) -> None:
    try:
        callable_()
    except signer.AuthorizationEnvelopeError as error:
        if required_text not in str(error):
            raise AssertionError(f"unexpected publication error: {error}") from error
    else:
        raise AssertionError("authorization publication unexpectedly succeeded")


def main() -> None:
    envelope = b'{"fixture":"signed-authorization-envelope"}\n'
    replacement = b'{"fixture":"replacement-must-not-win"}\n'
    with tempfile.TemporaryDirectory(prefix="nembra-auth-envelope-atomic-test-") as temporary:
        directory = Path(temporary)
        output = directory / "NembraCaptureFieldAuthorizationEnvelope.json"

        with mock.patch.object(
            signer.os,
            "fsync",
            side_effect=OSError("simulated durability failure"),
        ):
            expect_publication_error(
                lambda: signer.write_envelope_no_replace(output, envelope),
                "could not publish",
            )
        if output.exists():
            raise AssertionError("durability failure exposed a final authorization envelope")
        assert_no_staging(directory)

        with mock.patch.object(
            signer,
            "publish_file_no_replace",
            side_effect=OSError("simulated exclusive-rename failure"),
        ):
            expect_publication_error(
                lambda: signer.write_envelope_no_replace(output, envelope),
                "could not publish",
            )
        if output.exists():
            raise AssertionError("rename failure exposed a final authorization envelope")
        assert_no_staging(directory)

        with mock.patch.object(
            Path,
            "unlink",
            side_effect=AssertionError("successful publish attempted post-publication cleanup"),
        ):
            published = signer.write_envelope_no_replace(output, envelope)
        if published != output.resolve():
            raise AssertionError("published envelope path is not the exact resolved destination")
        if output.read_bytes() != envelope:
            raise AssertionError("published envelope bytes diverged")
        assert_no_staging(directory)

        expect_publication_error(
            lambda: signer.write_envelope_no_replace(output, replacement),
            "refusing to overwrite",
        )
        if output.read_bytes() != envelope:
            raise AssertionError("no-replace publication mutated the accepted envelope")
        assert_no_staging(directory)

    print("field authorization atomic-publication regression: PASS")


if __name__ == "__main__":
    main()
