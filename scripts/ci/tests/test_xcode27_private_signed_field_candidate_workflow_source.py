#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
WORKFLOWS = ROOT / ".github" / "workflows"


class PrivateSignedFieldCandidateWorkflowSourceTests(unittest.TestCase):
    def setUp(self):
        candidates = []
        for path in sorted(WORKFLOWS.glob("*.y*ml")):
            source = path.read_text()
            if "xcode27_signed_field_candidate.sh" in source:
                candidates.append((path, source))
        self.assertEqual(
            len(candidates),
            1,
            f"Expected exactly one private signed-field producer workflow, found {[str(p) for p, _ in candidates]}",
        )
        self.path, self.source = candidates[0]

    def test_intended_device_udid_is_not_a_visible_dispatch_input(self):
        self.assertNotRegex(
            self.source,
            re.compile(r"(?im)^\s*(field_)?device_?udid\s*:"),
            "A physical device UDID must not be exposed as a normal workflow_dispatch input.",
        )
        self.assertNotIn("github.event.inputs", self.source)
        self.assertNotIn("inputs.NEMBRA_FIELD_DEVICE_UDID", self.source)
        self.assertNotIn("inputs.field_device_udid", self.source)

    def test_intended_device_udid_comes_from_a_protected_secret(self):
        self.assertIn("NEMBRA_FIELD_DEVICE_UDID", self.source)
        self.assertRegex(
            self.source,
            re.compile(r"secrets\.[A-Za-z0-9_]*FIELD_DEVICE_UDID"),
            "The producer must receive the intended-device UDID from a protected Actions secret.",
        )

    def test_workflow_does_not_echo_or_upload_device_identifier(self):
        lowered = self.source.lower()
        self.assertNotRegex(lowered, re.compile(r"echo[^\n]*field_device_udid"))
        self.assertNotRegex(lowered, re.compile(r"echo[^\n]*device[_-]?udid"))
        self.assertNotRegex(
            lowered,
            re.compile(r"artifact[^\n]*(device[_-]?udid|field_device_udid)"),
            "The workflow must not name the device identifier as an uploaded artifact/evidence subject.",
        )

    def test_field_candidate_remains_explicitly_non_authorizing(self):
        self.assertIn("xcode27_signed_field_candidate.sh", self.source)
        self.assertNotIn("PassiveBluetoothExperimentOneFieldExecutionGate", self.source)
        self.assertNotIn("physical_authorization=GO", self.source)
        self.assertNotIn("permitsPhysicalProcedure", self.source)


if __name__ == "__main__":
    unittest.main()
