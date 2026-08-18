#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
PRODUCTION_HANDOFF = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"
CUSTODY_HANDOFF = REPOSITORY_ROOT / "docs" / "ES80_TODAY_PRIVATE_DEVICE_INPUT_CUSTODY.md"


class PrivateHelperHandoffPinTests(unittest.TestCase):
    RETIRED_COMMIT = "b479d851a54437ef394a4901c69db2d829d280e4"
    RETIRED_HEAD = "90d3578a1d39a1d019000583a712306b67786acf"
    RETIRED_HELPER_BLOB = "62b719e8d9afb34da6d35d696e80edf926442696"
    RETIRED_QA_RUN = "31350094260"
    RETIRED_QA_JOB = "93339137927"

    def documents(self) -> tuple[str, str]:
        return (
            PRODUCTION_HANDOFF.read_text(encoding="utf-8"),
            CUSTODY_HANDOFF.read_text(encoding="utf-8"),
        )

    def test_both_handoffs_are_retired_and_point_to_current_authority(self):
        production, custody = self.documents()
        for document in (production, custody):
            with self.subTest(document=document[:48]):
                self.assertIn("RETIRED", document)
                self.assertIn("NON-AUTHORIZING", document)
                self.assertIn("PHYSICAL STATUS: NO-GO", document)
                self.assertIn("ES80-AUTHENTICATED-STATIONARY-v1", document)
                self.assertIn("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md", document)

    def test_retired_helper_pins_cannot_be_reconstructed_from_handoffs(self):
        production, custody = self.documents()
        retired_markers = (
            self.RETIRED_COMMIT,
            self.RETIRED_HEAD,
            self.RETIRED_HELPER_BLOB,
            self.RETIRED_QA_RUN,
            self.RETIRED_QA_JOB,
            f"PRIVATE_INPUT_HELPER_COMMIT='{self.RETIRED_COMMIT}'",
            f"PRIVATE_INPUT_HELPER_BLOB='{self.RETIRED_HELPER_BLOB}'",
        )
        for document in (production, custody):
            with self.subTest(document=document[:48]):
                for marker in retired_markers:
                    self.assertNotIn(marker, document)

    def test_retired_handoffs_keep_secret_and_no_go_boundaries(self):
        production, custody = self.documents()
        self.assertIn("credentials", production.lower())
        self.assertIn("private device identifiers", custody)
        self.assertIn("AppKey/AppSecret", custody)
        self.assertIn("stay out of Git, logs, screenshots, public artifacts", custody)
        for document in (production, custody):
            with self.subTest(document=document[:48]):
                self.assertIn("DO NOT SCAN / DO NOT RUN", document)

    def test_retired_handoffs_have_no_fresh_leaf_materialization_recipe(self):
        production, custody = self.documents()
        stale_recipe_markers = (
            "UDID_FILENAME='es80-intended-device.udid'",
            'UDID_FILE="$PRIVATE_DIR/$UDID_FILENAME"',
            '--filename "$UDID_FILENAME"',
            "set `UDID_FILENAME` to a fresh leaf name",
        )
        for document in (production, custody):
            with self.subTest(document=document[:48]):
                for marker in stale_recipe_markers:
                    self.assertNotIn(marker, document)


if __name__ == "__main__":
    unittest.main()
