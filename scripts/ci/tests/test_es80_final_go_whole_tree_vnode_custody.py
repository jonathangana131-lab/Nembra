#!/usr/bin/env python3
"""Regression tests for Final-GO whole-tree source custody.

Portable tests use an injected event backend only at the internal audit seam so
we can deterministically verify namespace and queued-event rejection without
pretending Linux has macOS vnode authority. Darwin tests use the production
kqueue backend and replay the exact #3024 post-subject replacement timing.

No device, credential, Bluetooth, Tuya, signing, install, launch, or physical
operation occurs in this suite.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import select
import stat
import subprocess
import sys
import tempfile
import types
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "es80_authenticated_stationary_private_review_final_go_whole_tree.py"
SPEC = importlib.util.spec_from_file_location("nembra_final_go_whole_tree_vnode_subject", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Final-GO whole-tree vnode successor")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class FakeEvent:
    def __init__(self, ident: int, fflags: int = 1) -> None:
        self.ident = ident
        self.fflags = fflags


class FakeBackend(MODULE.EventBackend):
    def __init__(self) -> None:
        self.registered: list[int] = []
        self.pending: list[FakeEvent] = []
        self.closed = False

    def register(self, descriptor: int) -> None:
        self.registered.append(descriptor)

    def mark_mutation(self) -> None:
        if not self.registered:
            raise AssertionError("fake vnode backend has no registered subjects")
        self.pending.append(FakeEvent(self.registered[0], 0x4000))

    def events(self, timeout: float):
        del timeout
        if not self.pending:
            return []
        pending, self.pending = self.pending, []
        return pending

    def close(self) -> None:
        self.closed = True


class FinalGoWholeTreeVnodeCustodyTests(unittest.TestCase):
    def _candidate(self, root: Path) -> tuple[str, Path]:
        subprocess.run(["/usr/bin/git", "-C", str(root), "init", "-q"], check=True)
        subprocess.run(
            ["/usr/bin/git", "-C", str(root), "config", "user.email", "capture@nembra.invalid"],
            check=True,
        )
        subprocess.run(
            ["/usr/bin/git", "-C", str(root), "config", "user.name", "Nembra Capture QA"],
            check=True,
        )
        tracked = root / "A.swift"
        tracked.write_text("// exact accepted Final-GO bytes\n", encoding="utf-8")
        tracked.chmod(0o644)
        subprocess.run(["/usr/bin/git", "-C", str(root), "add", "A.swift"], check=True)
        subprocess.run(["/usr/bin/git", "-C", str(root), "commit", "-qm", "accepted candidate"], check=True)
        source = subprocess.check_output(
            ["/usr/bin/git", "-C", str(root), "rev-parse", "HEAD"], text=True
        ).strip().lower()

        for relative in MODULE.FIELD_INPUT_DIRECTORIES:
            path = root / relative
            path.mkdir(parents=True, exist_ok=True)
            self.assertTrue(stat.S_ISDIR(path.lstat().st_mode))
        for relative in MODULE.FIELD_INPUT_FILES:
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("PODS:\n", encoding="utf-8")
            path.chmod(0o600)
        return source, tracked

    @staticmethod
    def _replace_and_restore(tracked: Path, attacker: Path, sandbox: Path) -> None:
        accepted_inode = sandbox / "accepted-inode.swift"
        displaced_attacker = sandbox / "displaced-attacker.swift"
        os.replace(tracked, accepted_inode)
        os.replace(attacker, tracked)
        tracked.chmod(0o644)
        os.replace(tracked, displaced_attacker)
        os.replace(accepted_inode, tracked)
        tracked.chmod(0o644)

    def test_exact_parent_execution_is_bound_to_reviewed_2921_blob(self) -> None:
        repo = SCRIPT.resolve().parents[2]
        self.assertEqual(
            MODULE.PARENT_SOURCE,
            "471cc025b332f4df8b43a98d709710aeb4e0698f",
        )
        self.assertEqual(
            MODULE.PARENT_MODULE_GIT_BLOB,
            "48ce4bd8f933ae062eaaadd0d017d13c781a8c02",
        )
        entry = MODULE._parent._tree_entries(repo, MODULE.PARENT_SOURCE)[MODULE.PARENT_MODULE_PATH]
        self.assertEqual(entry[1], MODULE.PARENT_MODULE_GIT_BLOB)

    def test_clean_candidate_is_accepted_with_test_backend(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-whole-tree-clean-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, _ = self._candidate(root)
            backend = FakeBackend()
            entries = MODULE._audit_candidate_tree(root, source, backend_factory=lambda: backend)
            self.assertEqual(set(entries), {"A.swift"})
            self.assertTrue(backend.registered)
            self.assertTrue(backend.closed)

    def test_persistent_post_subject_replacement_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-whole-tree-persistent-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            attacker = sandbox / "attacker.swift"
            attacker.write_text("// attacker replacement after admitted read\n", encoding="utf-8")
            attacker.chmod(0o644)
            original = MODULE._parent._physical_blob_oid
            mutation_count = 0

            def mutate_after_admitted_read(current_root: Path, relative: str, mode: bytes, expected_oid: str) -> str:
                nonlocal mutation_count
                result = original(current_root, relative, mode, expected_oid)
                if relative == "A.swift" and mutation_count == 0:
                    os.replace(attacker, tracked)
                    tracked.chmod(0o644)
                    mutation_count += 1
                return result

            MODULE._parent._physical_blob_oid = mutate_after_admitted_read
            try:
                with self.assertRaisesRegex(RuntimeError, "physical tracked bytes differ|watched namespace changed"):
                    MODULE._audit_candidate_tree(root, source, backend_factory=FakeBackend)
            finally:
                MODULE._parent._physical_blob_oid = original
            self.assertEqual(mutation_count, 1)

    def test_queued_vnode_event_is_fail_closed_even_when_endpoint_bytes_are_clean(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-whole-tree-event-") as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            source, _ = self._candidate(root)
            backend = FakeBackend()
            original = MODULE._parent._audit_candidate_tree
            calls = 0

            def audit_then_mark(current_root: Path, current_source: str):
                nonlocal calls
                result = original(current_root, current_source)
                calls += 1
                # First call is the explicit audit inside MODULE._audit_candidate_tree.
                # Mark after the inherited audit returns so endpoint bytes remain exact;
                # the wrapper must still refuse queued mutation authority.
                if calls == 1:
                    backend.mark_mutation()
                return result

            MODULE._parent._audit_candidate_tree = audit_then_mark
            try:
                with self.assertRaisesRegex(MODULE.WholeTreeCustodyError, "whole-tree vnode mutation"):
                    MODULE._audit_candidate_tree(root, source, backend_factory=lambda: backend)
            finally:
                MODULE._parent._audit_candidate_tree = original
            self.assertEqual(calls, 2, "whole-tree custody did not run both inner and final audits")
            self.assertTrue(backend.closed)

    @unittest.skipUnless(sys.platform == "darwin" and hasattr(select, "kqueue"), "real vnode proof requires macOS kqueue")
    def test_real_kqueue_rejects_exact_3024_post_subject_replace_restore_race(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-whole-tree-kqueue-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            attacker = sandbox / "attacker.swift"
            attacker.write_text("// attacker transient replacement\n", encoding="utf-8")
            attacker.chmod(0o644)
            original = MODULE._parent._physical_blob_oid
            mutation_count = 0

            def mutate_after_admitted_read(current_root: Path, relative: str, mode: bytes, expected_oid: str) -> str:
                nonlocal mutation_count
                result = original(current_root, relative, mode, expected_oid)
                if relative == "A.swift" and mutation_count == 0:
                    self._replace_and_restore(tracked, attacker, sandbox)
                    mutation_count += 1
                return result

            MODULE._parent._physical_blob_oid = mutate_after_admitted_read
            try:
                with self.assertRaisesRegex(
                    MODULE.WholeTreeCustodyError,
                    "whole-tree vnode mutation|watched namespace changed",
                ):
                    MODULE._audit_candidate_tree(root, source)
            finally:
                MODULE._parent._physical_blob_oid = original
            self.assertEqual(mutation_count, 1)
            accepted_mode, accepted_oid = MODULE._parent._tree_entries(root, source)["A.swift"]
            self.assertEqual(
                MODULE._parent._physical_blob_oid(root, "A.swift", accepted_mode, accepted_oid),
                accepted_oid,
                "attack fixture did not restore accepted endpoint bytes",
            )

    @unittest.skipUnless(sys.platform == "darwin" and hasattr(select, "kqueue"), "real build-envelope proof requires macOS kqueue")
    def test_real_kqueue_suppresses_parent_build_result_after_transient_source_replacement(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-whole-tree-build-envelope-") as temporary:
            sandbox = Path(temporary)
            root = sandbox / "repo"
            root.mkdir()
            source, tracked = self._candidate(root)
            attacker = sandbox / "attacker.swift"
            attacker.write_text("// transient build-window attacker\n", encoding="utf-8")
            attacker.chmod(0o644)
            original_build = MODULE._parent.build
            calls = 0

            def fake_parent_build(**kwargs):
                nonlocal calls
                self.assertEqual(Path(kwargs["candidate_repo"]), root)
                self.assertEqual(kwargs["source"], source)
                self._replace_and_restore(tracked, attacker, sandbox)
                calls += 1
                return {"authority": "must-not-escape"}

            MODULE._parent.build = fake_parent_build
            try:
                with self.assertRaisesRegex(
                    MODULE.WholeTreeCustodyError,
                    "whole-tree vnode mutation|watched namespace changed",
                ):
                    MODULE.build(candidate_repo=root, source=source)
            finally:
                MODULE._parent.build = original_build
            self.assertEqual(calls, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
