import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from swarmcp.foundry_v17 import (  # noqa: E402
    FoundryPolicyError,
    RepositoryPressure,
    admission_plan,
)


class FoundryV17Tests(unittest.TestCase):
    def test_audited_nembra_pressure_denies_branch_multiplication(self):
        plan = admission_plan(
            requested_workers=30,
            ready_builders=20,
            active_builders=3,
            review_backlog=12,
            integration_backlog=8,
            retirement_candidates=50,
            pressure=RepositoryPressure(open_product_prs=297, open_branches=300),
        )
        self.assertEqual(plan["status"], "RETIREMENT")
        self.assertEqual(plan["newPrimaryBuilders"], 0)
        self.assertGreater(plan["retirementWorkers"], 0)
        self.assertFalse(plan["authorityGranted"])

    def test_red_main_allows_only_one_emergency_builder_over_budget(self):
        plan = admission_plan(
            requested_workers=30,
            ready_builders=8,
            active_builders=0,
            review_backlog=0,
            integration_backlog=0,
            retirement_candidates=30,
            pressure=RepositoryPressure(open_product_prs=297, open_branches=300),
            red_main=True,
        )
        self.assertEqual(plan["newPrimaryBuilders"], 1)
        self.assertTrue(plan["redMainEmergencyException"])

    def test_worker_count_is_capacity_not_quota(self):
        plan = admission_plan(
            requested_workers=30,
            ready_builders=2,
            active_builders=0,
            review_backlog=1,
            integration_backlog=1,
            retirement_candidates=0,
            pressure=RepositoryPressure(open_product_prs=2, open_branches=4),
        )
        self.assertEqual(plan["newPrimaryBuilders"], 2)
        self.assertEqual(plan["consideredWorkers"], 20)
        self.assertLess(plan["admittedWorkers"], 30)
        self.assertGreater(plan["parkedWorkers"], 0)

    def test_backlog_applies_builder_backpressure(self):
        plan = admission_plan(
            requested_workers=30,
            ready_builders=20,
            active_builders=0,
            review_backlog=7,
            integration_backlog=4,
            retirement_candidates=0,
            pressure=RepositoryPressure(open_product_prs=1, open_branches=2),
        )
        self.assertEqual(plan["newPrimaryBuilders"], 1)
        self.assertIn("review-backlog", plan["throttledBy"])
        self.assertIn("integration-backlog", plan["throttledBy"])

    def test_negative_pressure_fails_closed(self):
        with self.assertRaises(FoundryPolicyError):
            admission_plan(
                requested_workers=30,
                ready_builders=1,
                active_builders=0,
                review_backlog=0,
                integration_backlog=0,
                retirement_candidates=0,
                pressure=RepositoryPressure(open_product_prs=-1, open_branches=0),
            )


if __name__ == "__main__":
    unittest.main()
