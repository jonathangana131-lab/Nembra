#!/usr/bin/env python3
"""Expected-red V14 regression for canonical hardened Final-GO GitHub authority custody.

The canonical hardened composer is itself the authority-bearing import surface. Ordinary callers
must not be able to replace live GitHub PR/run/job/artifact metadata with a supplied callback.
Test-only seams belong behind a non-authorizing helper or private test adapter, not in the public
`build_final_go_record(...)` signature.
"""
from __future__ import annotations

import importlib.util
import inspect
from pathlib import Path
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / "es80_today_final_go_hardened.py"
spec = importlib.util.spec_from_file_location("hardened_final_go", MODULE_PATH)
hardened = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(hardened)


class HardenedFinalGoGitHubAuthorityCustodyTests(unittest.TestCase):
    def test_authority_bearing_public_builder_has_no_caller_github_metadata_seam(self):
        signature = inspect.signature(hardened.build_final_go_record)
        self.assertNotIn(
            "github_get_json",
            signature.parameters,
            "Canonical hardened Final GO must obtain live GitHub authority through its own "
            "custodied API path. A caller-selectable github_get_json callback can fabricate the "
            "PR/run/job/artifact subject while the local pinned workflow/blob checks still pass.",
        )

        source = inspect.getsource(hardened.build_final_go_record)
        self.assertIn(
            "foundation._api_get_json",
            source,
            "The authoritative builder should bind live GitHub metadata to the repository-owned "
            "API client rather than accepting caller-provided acceptance metadata.",
        )


if __name__ == "__main__":
    unittest.main()
