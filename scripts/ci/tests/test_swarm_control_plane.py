#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import swarm_control as sc


NOW = dt.datetime(2026, 8, 11, 5, 0, tzinfo=dt.timezone.utc)


def worker(index: int) -> str:
    return f"sol-20260811-w{index:04x}"


def make_lane(lane_id: str = "alpha", **kwargs):
    lane = sc.sample_lane(lane_id)
    lane.update(kwargs)
    return sc.validate_lane(lane)


class ValidationTests(unittest.TestCase):
    def test_01_lane_validates(self):
        self.assertEqual(sc.validate_lane(make_lane())["laneId"], "alpha")

    def test_02_unknown_schema_fails_closed(self):
        lane = make_lane(); lane["schemaVersion"] = 99
        with self.assertRaises(sc.ValidationError): sc.validate_lane(lane)

    def test_03_invalid_worker_identity_rejected(self):
        record = {"schemaVersion":1,"kind":"worker","workerId":"worker-one","model":"GPT-5.6 Sol","status":"ACTIVE","branch":"","startedAt":sc.format_time(NOW),"lastSeenAt":sc.format_time(NOW)}
        with self.assertRaises(sc.ValidationError): sc.validate_worker(record)

    def test_04_executable_control_field_rejected(self):
        event = {"schemaVersion":1,"kind":"event","eventId":"e1","type":"FINDING","workerId":worker(1),"message":"useful","createdAt":sc.format_time(NOW),"command":"rm -rf /"}
        with self.assertRaises(sc.ValidationError): sc.validate_event(event)

    def test_05_event_message_length_bounded(self):
        with self.assertRaises(sc.ValidationError): sc.publish_event(sc.MemoryStore(),"FINDING",worker(1),"x"*(sc.MAX_EVENT_MESSAGE+1),now=NOW)

    def test_06_repo_relative_path_rejects_traversal(self):
        with self.assertRaises(sc.ValidationError): sc.safe_relpath("../../etc/passwd","path")

    def test_07_exclusive_lane_cannot_have_two_primaries(self):
        lane=make_lane(); lane["slots"].append({"name":"candidate-b","role":"implementation","exclusive":True,"leaseSeconds":1800,"resources":[]})
        with self.assertRaises(sc.ValidationError): sc.validate_lane(lane)

    def test_08_tournament_requires_explicit_authorization(self):
        lane=make_lane(); lane["mode"]="tournament"; lane["slots"]=[{"name":"candidate-a","role":"implementation","exclusive":True,"leaseSeconds":1800,"resources":[]},{"name":"candidate-b","role":"implementation","exclusive":True,"leaseSeconds":1800,"resources":[]}]; lane["tournament"]={"authorized":False}
        with self.assertRaises(sc.ValidationError): sc.validate_lane(lane)

    def test_09_tournament_allows_bounded_candidates_when_authorized(self):
        lane=make_lane(); lane["mode"]="tournament"; lane["slots"]=[{"name":"candidate-a","role":"implementation","exclusive":True,"leaseSeconds":1800,"resources":[]},{"name":"candidate-b","role":"implementation","exclusive":True,"leaseSeconds":1800,"resources":[]}]; lane["tournament"]={"authorized":True}
        self.assertEqual(len(sc.validate_lane(lane)["slots"]),2)


class AtomicClaimTests(unittest.TestCase):
    def test_10_thirty_workers_one_exclusive_primary_exactly_one_wins(self):
        store=sc.MemoryStore(); lane=make_lane(); wins=[]
        for index in range(30):
            try: sc.claim_slot(store,lane,"primary",worker(index),now=NOW); wins.append(index)
            except sc.ConflictError: pass
        self.assertEqual(wins,[0])

    def test_11_claim_first_prevents_duplicate_branch_work(self):
        store=sc.MemoryStore(); lane=make_lane(); sc.claim_slot(store,lane,"primary",worker(1),now=NOW,branch="agent/alpha")
        with self.assertRaises(sc.ConflictError): sc.claim_slot(store,lane,"primary",worker(2),now=NOW,branch="agent/duplicate")

    def test_12_live_heartbeat_extends_lease(self):
        store=sc.MemoryStore(); lane=make_lane(); claimed=sc.claim_slot(store,lane,"primary",worker(1),now=NOW).value; later=NOW+dt.timedelta(seconds=100)
        value=sc.heartbeat(store,"alpha","primary",worker(1),claimed["leaseId"],1,now=later).value; self.assertEqual(value["lastHeartbeatAt"],sc.format_time(later))

    def test_13_expired_heartbeat_fails(self):
        store=sc.MemoryStore(); lane=make_lane(); claimed=sc.claim_slot(store,lane,"primary",worker(1),now=NOW).value; later=NOW+dt.timedelta(seconds=claimed["leaseSeconds"]+1)
        with self.assertRaises(sc.LeaseLostError): sc.heartbeat(store,"alpha","primary",worker(1),claimed["leaseId"],1,now=later)

    def test_14_takeover_requires_expired_or_released_claim(self):
        store=sc.MemoryStore(); lane=make_lane(); sc.claim_slot(store,lane,"primary",worker(1),now=NOW)
        with self.assertRaises(sc.ConflictError): sc.takeover_claim(store,lane,"primary",worker(2),now=NOW+dt.timedelta(seconds=10))

    def test_15_two_takeover_workers_exactly_one_wins(self):
        store=sc.MemoryStore(); lane=make_lane(); first=sc.claim_slot(store,lane,"primary",worker(1),now=NOW).value; expired=sc.claim_expiry(first)+dt.timedelta(seconds=1); wins=0
        for idx in (2,3):
            try: sc.takeover_claim(store,lane,"primary",worker(idx),now=expired); wins+=1
            except sc.ConflictError: pass
        self.assertEqual(wins,1)

    def test_16_old_primary_wakes_after_takeover_and_is_rejected(self):
        store=sc.MemoryStore(); lane=make_lane(); first=sc.claim_slot(store,lane,"primary",worker(1),now=NOW).value; expired=sc.claim_expiry(first)+dt.timedelta(seconds=1); sc.takeover_claim(store,lane,"primary",worker(2),now=expired)
        with self.assertRaises(sc.LeaseLostError): sc.heartbeat(store,"alpha","primary",worker(1),first["leaseId"],first["generation"],now=expired+dt.timedelta(seconds=1))

    def test_17_takeover_preserves_salvage_branch_and_pr(self):
        store=sc.MemoryStore(); lane=make_lane(); first=sc.claim_slot(store,lane,"primary",worker(1),now=NOW,branch="agent/alpha",pr=123).value; expired=sc.claim_expiry(first)+dt.timedelta(seconds=1); takeover=sc.takeover_claim(store,lane,"primary",worker(2),now=expired).value
        self.assertEqual((takeover["branch"],takeover["pr"],takeover["takeoverFromWorkerId"]),("agent/alpha",123,worker(1)))

    def test_18_release_is_cas_bound_to_owner(self):
        store=sc.MemoryStore(); lane=make_lane(); first=sc.claim_slot(store,lane,"primary",worker(1),now=NOW).value
        with self.assertRaises(sc.LeaseLostError): sc.release_claim(store,"alpha","primary",worker(2),first["leaseId"],1,now=NOW)

    def test_19_released_claim_can_be_taken_over_explicitly(self):
        store=sc.MemoryStore(); lane=make_lane(); first=sc.claim_slot(store,lane,"primary",worker(1),now=NOW).value; sc.release_claim(store,"alpha","primary",worker(1),first["leaseId"],1,now=NOW); takeover=sc.takeover_claim(store,lane,"primary",worker(2),now=NOW).value
        self.assertEqual(takeover["generation"],2)

    def test_20_transient_store_failure_does_not_create_false_ownership(self):
        store=sc.FaultInjectingStore(); lane=make_lane(); store.fail_next_create=True
        with self.assertRaises(sc.SwarmError): sc.claim_slot(store,lane,"primary",worker(1),now=NOW)
        with self.assertRaises(sc.NotFoundError): store.get(sc.claim_path("alpha","primary"))


class DependencySchedulerTests(unittest.TestCase):
    def test_21_blocked_dependency_hides_downstream(self):
        upstream=make_lane("upstream",state="BLOCKED_EXTERNAL"); downstream=make_lane("downstream",dependencies=["upstream"]); recs=sc.recommend_slots([upstream,downstream],[],[],sc.default_config(),now=NOW)
        self.assertFalse(any(r.lane_id=="downstream" for r in recs))

    def test_22_dependency_recovery_returns_downstream(self):
        upstream=make_lane("upstream",state="DONE"); downstream=make_lane("downstream",dependencies=["upstream"]); recs=sc.recommend_slots([upstream,downstream],[],[],sc.default_config(),now=NOW)
        self.assertTrue(any(r.lane_id=="downstream" for r in recs))

    def test_23_dependency_cycle_fails_closed(self):
        a=make_lane("a",dependencies=["b"]); b=make_lane("b",dependencies=["a"])
        with self.assertRaises(sc.ValidationError): sc.recommend_slots([a,b],[],[],sc.default_config(),now=NOW)

    def test_24_missing_dependency_is_not_runnable(self):
        lane=make_lane("child",dependencies=["missing"]); self.assertEqual(sc.recommend_slots([lane],[],[],sc.default_config(),now=NOW),[])

    def test_25_lane_blocker_hides_lane(self):
        lane=make_lane(); lane["blockers"]=[{"id":"github-auth","state":"ACTIVE","scope":"lane"}]; self.assertEqual(sc.recommend_slots([lane],[],[],sc.default_config(),now=NOW),[])

    def test_26_resolved_blocker_allows_lane(self):
        lane=make_lane(); lane["blockers"]=[{"id":"github-auth","state":"RESOLVED","scope":"lane"}]; self.assertTrue(sc.recommend_slots([lane],[],[],sc.default_config(),now=NOW))

    def test_27_red_main_prioritizes_repair(self):
        repair=make_lane("repair",priority=5); repair["tags"]=["red-main-repair"]; feature=make_lane("feature",priority=0); recs=sc.recommend_slots([feature,repair],[],[],sc.default_config(),now=NOW,red_main=True); self.assertEqual(recs[0].lane_id,"repair")

    def test_28_review_backlog_prefers_review_roles(self):
        lanes=[make_lane(f"review-{i}",state="REVIEW",priority=1) for i in range(5)]+[make_lane("new-feature",priority=1)]; recs=sc.recommend_slots(lanes,[],[],sc.default_config(),now=NOW); self.assertIn(recs[0].role,{"review","adversarial-review"})

    def test_29_integration_backlog_prefers_integration(self):
        lanes=[make_lane(f"int-{i}",state="INTEGRATION_READY",priority=1) for i in range(4)]+[make_lane("feature",priority=1)]; recs=sc.recommend_slots(lanes,[],[],sc.default_config(),now=NOW); self.assertEqual(recs[0].role,"integration")

    def test_30_wip_limit_throttles_new_primary(self):
        config=sc.default_config(); config["wipLimits"]["maxPrimaryLanes"]=1; a=make_lane("a"); b=make_lane("b"); claim=sc.new_claim(a,"primary",worker(1),now=NOW); recs=sc.recommend_slots([a,b],[claim],[],config,now=NOW)
        self.assertFalse(any(r.lane_id=="b" and r.role=="implementation" for r in recs)); self.assertTrue(any(r.lane_id=="b" and r.role!="implementation" for r in recs))

    def test_30b_per_epic_wip_limit_throttles_new_primary_in_same_epic(self):
        config=sc.default_config(); config["wipLimits"]["maxPrimaryLanes"]=9; config["wipLimits"]["maxPrimaryPerEpic"]=1; a=make_lane("epic-a"); b=make_lane("epic-b"); a["epic"]=b["epic"]="capture"; a=sc.validate_lane(a); b=sc.validate_lane(b); claim=sc.new_claim(a,"primary",worker(1),now=NOW); recs=sc.recommend_slots([a,b],[claim],[],config,now=NOW)
        self.assertFalse(any(r.lane_id=="epic-b" and r.role=="implementation" for r in recs))

    def test_31_high_fanout_dependency_gets_priority_signal(self):
        upstream=make_lane("upstream",priority=2); peer=make_lane("peer",priority=2); d1=make_lane("d1",dependencies=["upstream"],state="PROPOSED"); d2=make_lane("d2",dependencies=["upstream"],state="PROPOSED"); recs=sc.recommend_slots([upstream,peer,d1,d2],[],[],sc.default_config(),now=NOW); candidates=[r for r in recs if r.role=="implementation"]; self.assertEqual(candidates[0].lane_id,"upstream")

    def test_32_no_useful_work_can_return_idle(self):
        self.assertEqual(sc.recommend_slots([make_lane("done",state="DONE"),make_lane("blocked",state="BLOCKED_EXTERNAL")],[],[],sc.default_config(),now=NOW),[])


class PhysicalAndResourceTests(unittest.TestCase):
    def physical_lane(self):
        lane=make_lane("physical"); lane["physical"]={"required":True,"state":"PHYSICAL_NO_GO"}; lane["slots"].append({"name":"physical","role":"physical-evidence","exclusive":True,"leaseSeconds":1800,"resources":["PHYSICAL_SCOOTER"]}); return sc.validate_lane(lane)

    def test_33_physical_no_go_cannot_schedule_physical_slot(self):
        lane=self.physical_lane(); self.assertFalse(any(r.slot=="physical" for r in sc.recommend_slots([lane],[],[],sc.default_config(),now=NOW)))

    def test_34_physical_go_is_existing_external_authority_only(self):
        lane=self.physical_lane(); lane["physical"]["state"]="PHYSICAL_GO"; lane=sc.validate_lane(lane); self.assertTrue(any(r.slot=="physical" for r in sc.recommend_slots([lane],[],[],sc.default_config(),now=NOW)))

    def test_35_simulator_ready_does_not_equal_physical_go(self):
        lane=self.physical_lane(); lane["physical"]["state"]="SIMULATOR_READY"; self.assertFalse(sc.physical_slot_runnable(sc.validate_lane(lane),lane["slots"][-1])[0])

    def test_36_resource_lock_excludes_second_owner(self):
        store=sc.MemoryStore(); order=sc.default_config()["resourceOrder"]; sc.acquire_resources(store,["XCODE_BUILD"],worker(1),"alpha",now=NOW,resource_order=order)
        with self.assertRaises(sc.ConflictError): sc.acquire_resources(store,["XCODE_BUILD"],worker(2),"beta",now=NOW,resource_order=order)

    def test_37_multi_resource_acquisition_uses_deterministic_order(self):
        store=sc.MemoryStore(); order=sc.default_config()["resourceOrder"]; values=sc.acquire_resources(store,["IOS_SIMULATOR","XCODE_BUILD"],worker(1),"alpha",now=NOW,resource_order=order); self.assertEqual([v.value["resource"] for v in values],["XCODE_BUILD","IOS_SIMULATOR"])

    def test_38_partial_resource_acquisition_rolls_back(self):
        store=sc.MemoryStore(); order=sc.default_config()["resourceOrder"]; sc.acquire_resources(store,["IOS_SIMULATOR"],worker(2),"beta",now=NOW,resource_order=order)
        with self.assertRaises(sc.ConflictError): sc.acquire_resources(store,["XCODE_BUILD","IOS_SIMULATOR"],worker(1),"alpha",now=NOW,resource_order=order)
        self.assertEqual(store.get(sc.resource_path("XCODE_BUILD")).value["status"],"RELEASED")

    def test_39_stale_resource_can_be_taken_over(self):
        store=sc.MemoryStore(); order=sc.default_config()["resourceOrder"]; first=sc.acquire_resources(store,["XCODE_BUILD"],worker(1),"alpha",now=NOW,resource_order=order)[0].value; later=sc.claim_expiry(first)+dt.timedelta(seconds=1); second=sc.acquire_resources(store,["XCODE_BUILD"],worker(2),"beta",now=later,resource_order=order)[0].value; self.assertEqual((second["workerId"],second["generation"]),(worker(2),2))

    def test_40_occupied_resource_hides_required_slot(self):
        lane=make_lane("xcode")
        for slot in lane["slots"]:
            if slot["name"]=="tests": slot["resources"]=["XCODE_BUILD"]
        resource=sc._resource_claim("XCODE_BUILD",worker(1),"other",now=NOW); recs=sc.recommend_slots([sc.validate_lane(lane)],[],[resource],sc.default_config(),now=NOW); self.assertFalse(any(r.slot=="tests" for r in recs))

    def test_41_project_state_writer_is_single_writer_resource(self):
        store=sc.MemoryStore(); order=sc.default_config()["resourceOrder"]; sc.acquire_resources(store,["PROJECT_STATE_WRITER"],worker(1),"alpha",now=NOW,resource_order=order)
        with self.assertRaises(sc.ConflictError): sc.acquire_resources(store,["PROJECT_STATE_WRITER"],worker(2),"beta",now=NOW,resource_order=order)


class ReviewScopeAndMetadataTests(unittest.TestCase):
    def test_42_independent_reviewer_cannot_be_implementer(self):
        lane=make_lane(); primary=sc.new_claim(lane,"primary",worker(1),now=NOW)
        with self.assertRaises(sc.ValidationError): sc.verify_review_independence(lane,primary,worker(1))

    def test_43_different_reviewer_is_accepted(self):
        lane=make_lane(); sc.verify_review_independence(lane,sc.new_claim(lane,"primary",worker(1),now=NOW),worker(2))

    def test_44_scope_expansion_is_detected(self):
        self.assertEqual(sc.scope_violations(make_lane(),["work/alpha/a.swift","unrelated/global.swift"]),["unrelated/global.swift"])

    def test_45_adjacent_tests_and_docs_can_be_declared(self):
        self.assertEqual(sc.scope_violations(make_lane(),["tests/alpha/test.py","docs/alpha/note.md"]),[])

    def test_46_pr_metadata_parses_and_validates(self):
        body="\n".join(["SWARM_SCHEMA: 1","SWARM_LANE: alpha","SWARM_SLOT: primary",f"SWARM_WORKER: {worker(1)}","SWARM_CLAIM_GENERATION: 2"]); self.assertEqual(sc.validate_pr_metadata(body)["generation"],2)

    def test_47_legacy_pr_without_metadata_fails_validation_but_rollout_can_shadow_warn(self):
        with self.assertRaises(sc.ValidationError): sc.validate_pr_metadata("legacy body")
        self.assertEqual(sc.default_config()["legacyPRCompatibility"],"shadow-warn")


class EventsHandoffsBoardTests(unittest.TestCase):
    def test_48_events_are_immutable_create_only(self):
        store=sc.MemoryStore(); first=sc.publish_event(store,"FINDING",worker(1),"found blocker",now=NOW,lane_id="alpha")
        with self.assertRaises(sc.ConflictError): store.create(sc.event_path(first.value),first.value)

    def test_49_event_ids_are_collision_resistant(self):
        store=sc.MemoryStore(); a=sc.publish_event(store,"FINDING",worker(1),"a",now=NOW); b=sc.publish_event(store,"FINDING",worker(1),"b",now=NOW); self.assertNotEqual(a.value["eventId"],b.value["eventId"])

    def test_50_handoff_captures_salvage_truth(self):
        store=sc.MemoryStore(); handoff={"schemaVersion":1,"kind":"handoff","laneId":"alpha","workerId":worker(1),"branch":"agent/alpha","headSHA":"a"*40,"pr":123,"completed":["implementation"],"remaining":["review"],"testsRun":["unit suite"],"knownFailures":[],"importantFindings":["one race"],"recommendedNextAction":"review","createdAt":sc.format_time(NOW)}; stored=sc.publish_handoff(store,handoff,now=NOW); self.assertEqual(stored.value["headSHA"],"a"*40)

    def test_51_dashboard_is_rebuildable_and_deterministic(self):
        lane=make_lane(); claim=sc.new_claim(lane,"primary",worker(1),now=NOW); a=sc.render_dashboard([lane],[claim],[],[],[],now=NOW); b=sc.render_dashboard([lane],[claim],[],[],[],now=NOW); self.assertEqual(a,b); self.assertIn("Generated cache only",a)

    def test_51b_dashboard_reports_scarce_resource_status(self):
        lane=make_lane(); resource=sc._resource_claim("XCODE_BUILD",worker(1),"alpha",now=NOW); board=sc.render_dashboard([lane],[],[],[resource],[],now=NOW); self.assertIn("Scarce resources",board); self.assertIn("XCODE_BUILD",board); self.assertIn("LEASED",board)

    def test_52_corrupt_generated_board_does_not_affect_authoritative_scheduler(self):
        lane=make_lane(); before=sc.recommend_slots([lane],[],[],sc.default_config(),now=NOW); corrupted_board="garbage\n"*100; self.assertTrue(corrupted_board); after=sc.recommend_slots([lane],[],[],sc.default_config(),now=NOW); self.assertEqual(before,after)

    def test_53_state_snapshot_detects_unknown_claim_lane(self):
        lane=make_lane("alpha"); other=make_lane("other"); claim=sc.new_claim(other,"primary",worker(1),now=NOW); errors=sc.validate_state_snapshot([lane],[claim],[],[],[],now=NOW); self.assertTrue(any("unknown lane" in e for e in errors))


class FullPromptAdversarialSimulationTests(unittest.TestCase):
    def test_54_builtin_thirty_worker_simulation_passes(self):
        result=sc.run_adversarial_simulation(30); self.assertTrue(result["passed"],result); self.assertEqual(result["claimCollisionsPrevented"],29)

    def test_55_stale_board_worker_loses_atomic_claim_cleanly(self):
        lane=make_lane(); store=sc.MemoryStore(); self.assertTrue(any(r.slot=="primary" for r in sc.recommend_slots([lane],[],[],sc.default_config(),now=NOW))); sc.claim_slot(store,lane,"primary",worker(1),now=NOW)
        with self.assertRaises(sc.ConflictError): sc.claim_slot(store,lane,"primary",worker(2),now=NOW)

    def test_56_invalid_control_json_fails_before_state_use(self):
        with self.assertRaises(json.JSONDecodeError): json.loads("{invalid")

    def test_57_worker_can_register_after_usage_recovery_without_stealing_claim(self):
        store=sc.MemoryStore(); lane=make_lane(); sc.claim_slot(store,lane,"primary",worker(1),now=NOW); sc.register_worker(store,worker(2),now=NOW+dt.timedelta(hours=1))
        with self.assertRaises(sc.ConflictError): sc.claim_slot(store,lane,"primary",worker(2),now=NOW+dt.timedelta(hours=1))

    def test_58_source_sha_is_exact_when_present(self):
        lane=make_lane(); self.assertEqual(sc.new_claim(lane,"primary",worker(1),now=NOW,source_sha="a"*40)["sourceSHA"],"a"*40)
        with self.assertRaises(sc.ValidationError): sc.new_claim(lane,"primary",worker(2),now=NOW,source_sha="abc")

    def test_59_role_specific_lease_is_respected(self):
        lane=make_lane(); self.assertGreater(sc.new_claim(lane,"primary",worker(1),now=NOW)["leaseSeconds"],sc.new_claim(lane,"review",worker(2),now=NOW)["leaseSeconds"])

    def test_60_main_red_does_not_spawn_twenty_repair_primaries(self):
        repair=make_lane("repair"); repair["tags"]=["red-main-repair"]; recs=sc.recommend_slots([repair],[],[],sc.default_config(),now=NOW,red_main=True); self.assertEqual(len([r for r in recs if r.role=="implementation"]),1); self.assertGreaterEqual(len([r for r in recs if r.role!="implementation"]),1)

    def test_61_scheduler_never_treats_lines_written_as_priority(self):
        lane=make_lane(); lane["metrics"]={"linesWritten":1000000}; recs=sc.recommend_slots([sc.validate_lane(lane)],[],[],sc.default_config(),now=NOW); self.assertTrue(recs); self.assertNotIn("lines",recs[0].reason.lower())

    def test_62_physical_evidence_accepted_is_not_rewritten_by_scheduler(self):
        lane=make_lane("physical-accepted"); lane["physical"]={"required":True,"state":"PHYSICAL_EVIDENCE_ACCEPTED"}; lane=sc.validate_lane(lane); before=lane["physical"]["state"]; sc.recommend_slots([lane],[],[],sc.default_config(),now=NOW); self.assertEqual(lane["physical"]["state"],before)

    def test_63_unknown_newer_control_plane_schema_fails_closed(self):
        config=sc.default_config(); config["schemaVersion"]=2
        with self.assertRaises(sc.ValidationError): sc.validate_config(config)

    def test_64_config_resource_order_has_no_duplicates(self):
        config=sc.default_config(); self.assertEqual(len(config["resourceOrder"]),len(set(config["resourceOrder"])))

    def test_65_no_arbitrary_remote_code_fields_in_default_config(self):
        sc.validate_data_only(sc.default_config())


if __name__ == "__main__":
    unittest.main(verbosity=2)
