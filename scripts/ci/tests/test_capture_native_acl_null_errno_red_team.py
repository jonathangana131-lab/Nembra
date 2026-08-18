#!/usr/bin/env python3
"""Exploit-positive classifier for unclassified native ACL acquisition failure."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location(
        "nembra_native_acl_null_errno_red_team", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CaptureNativeACLNullErrnoRedTeamTests(unittest.TestCase):
    def test_null_acl_get_fd_with_zero_errno_is_promoted_to_empty_baseline(self) -> None:
        helper = load()
        library = mock.Mock()
        library.acl_get_fd.return_value = None
        library.acl_init.return_value = 0xC0FFEE
        library.acl_free.return_value = 0

        with mock.patch.object(helper, "_darwin_acl_library", return_value=library):
            baseline = helper._capture_fd_acl_baseline(73)

        self.assertEqual(baseline, 0xC0FFEE)
        library.acl_get_fd.assert_called_once_with(73)
        library.acl_init.assert_called_once_with(0)
        library.acl_free.assert_not_called()

        print(
            "NEMBRA_NATIVE_ACL_NULL_ERRNO_ACCEPTED "
            "aclGetFdNull=true errnoZero=true classifiedAsAbsent=true emptyBaselineMinted=true"
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
