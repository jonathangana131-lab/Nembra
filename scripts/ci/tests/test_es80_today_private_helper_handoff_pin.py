#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
PRODUCTION_HANDOFF = REPOSITORY_ROOT / "docs" / "ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md"
CUSTODY_HANDOFF = REPOSITORY_ROOT / "docs" / "ES80_TODAY_PRIVATE_DEVICE_INPUT_CUSTODY.md"


class PrivateHelperHandoffPinTests(unittest.TestCase):
    HISTORICAL_PINS = (
        "b479d851a54437ef394a4901c69db2d829d280e4",
        "90d3578a1d39a1d019000583a712306b67786acf",
        "62b719e8d9afb34da6d35d696e80edf926442696",
        "31350094260",
        "93339137927",
    )

    def documents(self) -> tuple[str, str]:
        return (
            PRODUCTION_HANDOFF.read_text(encoding="utf-8"),
            CUSTODY_HANDOFF.read_text(encoding="utf-8"),
        )

    def test_both_historical_handoffs_are_retired_and_non_authorizing(self):
        production, custody = self.documents()
        for document in (production, custody):
            with self.subTest(document=document[:48]):
                self.assertIn("RETIRED / NON-AUTHORIZING", document)
                self.assertIn("PHYSICAL STATUS: NO-GO", document)
                self.assertIn("ES80-AUTHENTICATED-STATIONARY-v1", document)
                self.assertIn("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md", document)

    def test_historical_helper_pins_are_not_published_as_current_authority(self):
        production, custody = self.documents()
        for document in (production, custody):
            with self.subTest(document=document[:48]):
                for pin in self.HISTORICAL_PINS:
                    self.assertNotIn(pin, document)
                self.assertNotIn("PRIVATE_INPUT_HELPER_COMMIT=", document)
                self.assertNotIn("PRIVATE_INPUT_HELPER_BLOB=", document)
                self.assertNotIn("UDID_FILENAME=", document)
                self.assertNotIn("--filename", document)

    def test_retirement_preserves_private_input_truth_boundary_without_recipe(self):
        production, custody = self.documents()

        self.assertIn("Historical TODAY producer/helper scripts", production)
        self.assertIn("Do not recover an older commit", production)
        self.assertIn("private device identifiers", custody)
        self.assertIn("must stay out of Git, logs, screenshots", custody)
        self.assertNotIn("```bash", production)
        self.assertNotIn("```bash", custody)


if __name__ == "__main__":
    unittest.main()
