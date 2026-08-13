#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import importlib.util
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location("swarm_v16_record_objective", ROOT / "scripts/swarm_v16_record_objective.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)

from swarmcp import ValidationError, add_blocker, seed_nembra_graph


class ObjectiveIntegrationTests(unittest.TestCase):
    def record(self, graph, objective="capture-standalone-build"):
        return MODULE.record_objective_integration(
            graph,
            objective_id=objective,
            pr=3168,
            source_head="a" * 40,
            merge_sha="b" * 40,
            acceptance_runs=["31654041247", "31654209978"],
            review_refs=["4922282569"],
            affected_paths=["NembraCapture.xcodeproj", "NembraApp/Features/Research", "Packages/NembraBluetoothCapture"],
        )

    def test_nonphysical_software_objective_closes_with_bound_evidence(self):
        graph = seed_nembra_graph()
        result = self.record(graph)
        objective = graph["objectives"]["capture-standalone-build"]
        self.assertEqual(result["status"], "DONE")
        self.assertFalse(result["idempotent"])
        self.assertEqual(objective["status"], "DONE")
        self.assertEqual(objective["integrationState"], "MAIN")
        self.assertTrue(all(objective["finishSatisfied"]))
        self.assertEqual(objective["featureGenome"]["functionality"]["state"], "ACCEPTED")
        self.assertEqual(objective["featureGenome"]["testing"]["state"], "ACCEPTED")
        self.assertEqual(objective["featureGenome"]["integration"]["state"], "ACCEPTED")
        self.assertEqual(objective["featureGenome"]["physicalTruth"]["state"], "NOT_APPLICABLE")
        self.assertFalse(result["physicalAuthorityPromoted"])
        self.assertEqual(len(result["evidenceIds"]), 3)
        branch = graph["branches"]["mission/capture-stationary"]
        self.assertEqual(branch["world"], "MAIN")
        self.assertEqual(branch["source"]["mergeSHA"], "b" * 40)

    def test_same_integration_is_idempotent(self):
        graph = seed_nembra_graph()
        first = self.record(graph)
        evidence_count = len(graph["evidence"])
        memory_count = len(graph["memory"])
        second = self.record(graph)
        self.assertFalse(first["idempotent"])
        self.assertTrue(second["idempotent"])
        self.assertEqual(len(graph["evidence"]), evidence_count)
        self.assertEqual(len(graph["memory"]), memory_count)

    def test_physical_or_user_dependent_objective_cannot_be_auto_accepted(self):
        graph = seed_nembra_graph()
        graph["objectives"]["capture-signed-build"]["status"] = "DONE"
        with self.assertRaisesRegex(ValidationError, "physical/user-dependent"):
            self.record(graph, objective="capture-installation")
        self.assertNotEqual(graph["objectives"]["capture-installation"]["status"], "DONE")

    def test_unfinished_dependency_cannot_be_bypassed(self):
        graph = seed_nembra_graph()
        with self.assertRaisesRegex(ValidationError, "dependencies are not DONE"):
            self.record(graph, objective="capture-tuya-auth")

    def test_unresolved_p0_or_p1_blocks_software_objective_close(self):
        graph = seed_nembra_graph()
        add_blocker(
            graph,
            blocker_id="standalone-real-blocker",
            mission_id="capture-stationary",
            objective_id="capture-standalone-build",
            symptom="standalone build is broken",
            severity="P0",
            exit_condition="accepted build succeeds",
            legitimate_new=True,
        )
        with self.assertRaisesRegex(ValidationError, "unresolved P0/P1"):
            self.record(graph)
        self.assertNotEqual(graph["objectives"]["capture-standalone-build"]["status"], "DONE")

    def test_integration_references_and_paths_are_bounded(self):
        graph = seed_nembra_graph()
        with self.assertRaisesRegex(ValidationError, "numeric GitHub PR review IDs"):
            MODULE.record_objective_integration(
                graph,
                objective_id="capture-standalone-build",
                pr=3168,
                source_head="a" * 40,
                merge_sha="b" * 40,
                acceptance_runs=["31654041247"],
                review_refs=["not-a-review"],
                affected_paths=["Capture"],
            )
        with self.assertRaisesRegex(ValidationError, "affected path"):
            MODULE.record_objective_integration(
                graph,
                objective_id="capture-standalone-build",
                pr=3168,
                source_head="a" * 40,
                merge_sha="b" * 40,
                acceptance_runs=["31654041247"],
                review_refs=["4922282569"],
                affected_paths=["../outside"],
            )


class ObjectiveIntegrationWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / ".github/workflows/swarm-v16-objective-integrate-command.yml").read_text(encoding="utf-8")

    def test_command_is_owner_only_and_uses_trusted_default_branch_code(self):
        source = self.source
        self.assertIn("github.actor == github.repository_owner", source)
        self.assertIn("startsWith(github.event.comment.body, '/v16-objective-integrate ')", source)
        self.assertIn("ref: ${{ github.event.repository.default_branch }}", source)
        self.assertIn("persist-credentials: false", source)
        self.assertIn("fetch-depth: 0", source)
        self.assertNotIn("pull_request.head.sha", source)

    def test_command_verifies_runs_reviews_merged_pr_and_unchanged_paths(self):
        source = self.source
        for fragment in (
            "pr.merged_at",
            "pr.head.sha !== process.env.SOURCE_HEAD",
            "pr.merge_commit_sha !== process.env.MERGE_SHA",
            "pr.base.ref !== context.payload.repository.default_branch",
            "github.rest.actions.getWorkflowRun",
            "run.status !== 'completed' || run.conclusion !== 'success'",
            "run.head_sha === process.env.SOURCE_HEAD",
            "github.rest.pulls.getReview",
            "review.commit_id !== process.env.SOURCE_HEAD",
            "review.body.includes(runId)",
            "git merge-base --is-ancestor \"$MERGE_SHA\" HEAD",
            "git diff --name-only \"$MERGE_SHA..HEAD\" -- \"$path\"",
            "Evidence-bound path changed after integration",
        ):
            self.assertIn(fragment, source)
        self.assertIn("scripts/swarm_v16_record_objective.py", source)
        self.assertIn("--state-branch swarm-state", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
