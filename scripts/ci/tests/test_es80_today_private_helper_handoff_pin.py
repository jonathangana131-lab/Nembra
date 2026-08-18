#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
PRODUCTION_HANDOFF = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"
CUSTODY_HANDOFF = REPOSITORY_ROOT / "docs" / "ES80_TODAY_PRIVATE_DEVICE_INPUT_CUSTODY.md"


class PrivateHelperHandoffRetirementTests(unittest.TestCase):
    LEGACY_OPERATIONAL_MARKERS = (
        "b479d851a54437ef394a4901c69db2d829d280e4",
        "90d3578a1d39a1d019000583a712306b67786acf",
        "62b719e8d9afb34da6d35d696e80edf926442696",
        "31350094260",
        "93339137927",
        "PRIVATE_INPUT_HELPER_COMMIT=",
        "PRIVATE_INPUT_HELPER_BLOB=",
        "UDID_FILENAME=",
        "READY_TO_INVOKE_SIGNED_FIELD_PRODUCER",
    )

    def documents(self) -> tuple[str, str]:
        return (
            PRODUCTION_HANDOFF.read_text(encoding="utf-8"),
            CUSTODY_HANDOFF.read_text(encoding="utf-8"),
        )

    def test_both_handoffs_are_explicitly_retired_non_authorizing_and_no_go(self):
        production, custody = self.documents()
        for document in (production, custody):
            with self.subTest(document=document[:48]):
                self.assertIn("RETIRED", document)
                self.assertIn("NON-AUTHORIZING", document)
                self.assertIn("PHYSICAL STATUS: NO-GO", document)
                self.assertIn("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md", document)
                self.assertIn("ES80-AUTHENTICATED-STATIONARY-v1", document)
                self.assertIn("DO NOT SCAN / DO NOT RUN", document)

    def test_retired_handoffs_publish_no_legacy_helper_pin_or_materialization_recipe(self):
        production, custody = self.documents()
        for document in (production, custody):
            with self.subTest(document=document[:48]):
                for marker in self.LEGACY_OPERATIONAL_MARKERS:
                    self.assertNotIn(marker, document)

    def test_retired_handoffs_require_current_live_authority_instead_of_history(self):
        production, custody = self.documents()

        self.assertIn("live authenticated-stationary lineage and fresh GitHub state", production)
        self.assertIn("Do not recover an older commit", production)
        self.assertIn("current reviewed private-input/provisioning authority named by the live lineage", custody)
        self.assertIn("Do not copy an old helper SHA or frozen source pin", custody)

    def test_private_input_security_boundary_survives_retirement_without_becoming_authority(self):
        custody = CUSTODY_HANDOFF.read_text(encoding="utf-8")

        self.assertIn("private device identifiers", custody)
        self.assertIn("AppKey/AppSecret", custody)
        self.assertIn("must stay out of Git, logs, screenshots, public artifacts, and process arguments", custody)
        self.assertIn("That boundary is not physical authorization", custody)


if __name__ == "__main__":
    unittest.main()
