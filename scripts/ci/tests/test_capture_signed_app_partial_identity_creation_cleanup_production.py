#!/usr/bin/env python3
"""Regress fail-closed cleanup when dedicated build identity creation aborts."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
ORIGIN_HELPER = REPOSITORY / "scripts/ci/capture_signed_app_build_origin_custody.py"


def load_helper():
    spec = importlib.util.spec_from_file_location(
        "capture_signed_app_build_origin_custody_partial_cleanup",
        ORIGIN_HELPER,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {ORIGIN_HELPER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureSignedAppPartialIdentityCreationCleanupProductionTests(unittest.TestCase):
    @staticmethod
    def _missing_directory_service_record(*_args, **_kwargs):
        return mock.Mock(returncode=1)

    def test_partial_creation_failure_requires_strict_absence_proof(self) -> None:
        helper = load_helper()
        creation_failure = subprocess.CalledProcessError(
            71,
            ["/usr/bin/dscl", ".", "-create", "/Groups/nembrabuildtest", "PrimaryGroupID", "55001"],
        )

        with (
            mock.patch.object(helper.sys, "platform", "darwin"),
            mock.patch.object(helper.os, "geteuid", return_value=0),
            mock.patch.object(
                helper.subprocess,
                "run",
                side_effect=self._missing_directory_service_record,
            ),
            mock.patch.object(
                helper,
                "_run_root_checked",
                side_effect=[mock.Mock(returncode=0), creation_failure],
            ),
            mock.patch.object(helper, "_remove_local_build_identity") as remove_identity,
            self.assertRaises(subprocess.CalledProcessError),
        ):
            helper._create_local_build_identity(
                "nembrabuildtest",
                55001,
                55001,
                Path("/private/tmp/nembra-build-home"),
            )

        remove_identity.assert_called_once_with(
            "nembrabuildtest",
            55001,
            require_absent=True,
        )

    def test_cleanup_failure_becomes_authoritative_creation_failure(self) -> None:
        helper = load_helper()
        creation_failure = subprocess.CalledProcessError(
            71,
            ["/usr/bin/dscl", ".", "-create", "/Groups/nembrabuildtest", "PrimaryGroupID", "55001"],
        )
        cleanup_failure = helper.BuildOriginCustodyError(
            "partial build identity survived strict cleanup"
        )

        with (
            mock.patch.object(helper.sys, "platform", "darwin"),
            mock.patch.object(helper.os, "geteuid", return_value=0),
            mock.patch.object(
                helper.subprocess,
                "run",
                side_effect=self._missing_directory_service_record,
            ),
            mock.patch.object(
                helper,
                "_run_root_checked",
                side_effect=[mock.Mock(returncode=0), creation_failure],
            ),
            mock.patch.object(
                helper,
                "_remove_local_build_identity",
                side_effect=cleanup_failure,
            ) as remove_identity,
            self.assertRaisesRegex(
                helper.BuildOriginCustodyError,
                "partial build identity survived strict cleanup",
            ),
        ):
            helper._create_local_build_identity(
                "nembrabuildtest",
                55001,
                55001,
                Path("/private/tmp/nembra-build-home"),
            )

        remove_identity.assert_called_once_with(
            "nembrabuildtest",
            55001,
            require_absent=True,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
