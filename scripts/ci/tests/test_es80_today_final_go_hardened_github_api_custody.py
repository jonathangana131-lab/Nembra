#!/usr/bin/env python3
"""V14 regression for canonical hardened Final-GO GitHub authority custody."""
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
            "custodied API path. A caller-selectable callback can fabricate PR/run/job/artifact "
            "metadata while local pinned workflow/blob checks still pass.",
        )

        source = inspect.getsource(hardened.build_final_go_record)
        self.assertIn("github_get_json=foundation._api_get_json", source)
        self.assertIn(
            "if github_get_json is not foundation._api_get_json:",
            source,
            "The private foundation seam must not be allowed to swap the repository-owned API client.",
        )
        self.assertIn(
            "private Final GO foundation attempted to replace live GitHub authority",
            source,
        )


if __name__ == "__main__":
    unittest.main()
