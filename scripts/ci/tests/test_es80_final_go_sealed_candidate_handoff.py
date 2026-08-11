#!/usr/bin/env python3
"""Permanent acceptance for the Final-GO sealed candidate-authority handoff.

The watcher release red teams are correct: no finite final drain can prove a
mutable checkout remains unchanged after the drain. Production therefore has a
one-way semantic boundary instead. The complete installed/retained signed record
is produced while #3042 custody is still live; the checkout is then retired as
an authority input before watcher teardown. Mutations before retirement remain
fatal. Mutations after retirement cannot influence the already-complete record
and any attempted candidate Git/blob reopen is rejected.
"""
from __future__ import annotations

import ast
import contextlib
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import types
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
BASE_PATH = "scripts/ci/es80_authenticated_stationary_final_go.py"
BASE_SOURCE = "3fdd32551831c3469e0853ddcee8fa828d38b87b"
BASE_BLOB = "b0664c734004c2265b05d23ec58756806ff62f2c"
EXPECTED_PREDECESSOR = "cb36f9265f08708c8e47564f62f4857aeae7af0f"
EXPECTED_PREDECESSOR_BLOB = "baef9de23a680bedf16f9f7b367f45f7710ac0c6"

SPEC = importlib.util.spec_from_file_location("nembra_final_go_sealed_handoff_subject", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load sealed-handoff Final-GO subject")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def _git_environment() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
    }


def _git(*arguments: str) -> bytes:
    return subprocess.run(
        ["/usr/bin/git", "-C", str(ROOT), *arguments],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=_git_environment(),
    ).stdout


def _canonical_blob_oid(payload: bytes, accepted_oid: str) -> str:
    raw = b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    if len(accepted_oid) == 40:
        return hashlib.sha1(raw).hexdigest()
    if len(accepted_oid) == 64:
        return hashlib.sha256(raw).hexdigest()
    raise AssertionError("unsupported Git object width")


def _accepted_blob(source: str, path: str, expected_blob: str) -> bytes:
    actual = _git("rev-parse", f"{source}:{path}").decode("ascii").strip().lower()
    if actual != expected_blob:
        raise AssertionError(f"accepted blob moved: expected {expected_blob}, got {actual}")
    payload = _git("cat-file", "blob", actual)
    if _canonical_blob_oid(payload, actual) != actual:
        raise AssertionError("accepted Git blob bytes failed canonical identity")
    return payload


def _function(tree: ast.AST, name: str) -> ast.FunctionDef:
    matches = [node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef) and node.name == name]
    if len(matches) != 1:
        raise AssertionError(f"expected one function named {name}, found {len(matches)}")
    return matches[0]


def _call_name(node: ast.Call) -> str:
    current: ast.AST = node.func
    parts: list[str] = []
    while isinstance(current, ast.Attribute):
        parts.append(current.attr)
        current = current.value
    if isinstance(current, ast.Name):
        parts.append(current.id)
    return ".".join(reversed(parts))


def _call_positions(function: ast.FunctionDef, suffix: str) -> list[tuple[int, int]]:
    return sorted(
        (node.lineno, node.col_offset)
        for node in ast.walk(function)
        if isinstance(node, ast.Call) and _call_name(node).endswith(suffix)
    )


class _FakeBase:
    def __init__(self) -> None:
        self.git_calls: list[tuple[object, ...]] = []
        self.git_bytes_calls: list[tuple[object, ...]] = []

        def git(*arguments: object, **_kwargs: object) -> str:
            self.git_calls.append(arguments)
            return "original-git"

        def git_bytes(*arguments: object, **_kwargs: object) -> bytes:
            self.git_bytes_calls.append(arguments)
            return b"original-git-bytes"

        self.git = git
        self.git_bytes = git_bytes
        self.original_git = git
        self.original_git_bytes = git_bytes

    @staticmethod
    def canon(value: str, _name: str) -> str:
        return value.strip().lower()


class FinalGoSealedCandidateHandoffTests(unittest.TestCase):
    def test_exact_predecessor_is_captured_before_execution(self) -> None:
        self.assertEqual(MODULE.PREDECESSOR_SOURCE, EXPECTED_PREDECESSOR)
        self.assertEqual(MODULE.PREDECESSOR_MODULE_GIT_BLOB, EXPECTED_PREDECESSOR_BLOB)
        payload = MODULE._capture_predecessor_blob(ROOT)
        self.assertEqual(
            MODULE._canonical_git_blob_oid(payload, EXPECTED_PREDECESSOR_BLOB),
            EXPECTED_PREDECESSOR_BLOB,
        )
        self.assertNotIn("importlib.import_module", SCRIPT.read_text(encoding="utf-8"))

    def test_handoff_requires_completed_install_and_retained_signed_subject(self) -> None:
        good = {
            "privateFieldInstall": {"installed": True},
            "retainedSignedFieldArtifact": {"retained": True},
            "physicalResultCollected": False,
        }
        self.assertIs(MODULE._require_sealed_final_go_record(good), good)

        for missing in tuple(good):
            bad = dict(good)
            bad.pop(missing)
            with self.subTest(missing=missing), self.assertRaises(MODULE._SealedHandoffError):
                MODULE._require_sealed_final_go_record(bad)
        for key in ("privateFieldInstall", "retainedSignedFieldArtifact"):
            bad = dict(good)
            bad[key] = None
            with self.subTest(none=key), self.assertRaises(MODULE._SealedHandoffError):
                MODULE._require_sealed_final_go_record(bad)
        bad_physical = dict(good)
        bad_physical["physicalResultCollected"] = True
        with self.assertRaises(MODULE._SealedHandoffError):
            MODULE._require_sealed_final_go_record(bad_physical)

    def test_retirement_blocks_candidate_git_and_blob_reopen_until_teardown(self) -> None:
        base = _FakeBase()
        original_physical = MODULE._PREDECESSOR_PHYSICAL_BLOB_OID
        MODULE._PREDECESSOR_PHYSICAL_BLOB_OID = lambda *_args: "accepted"
        try:
            with MODULE._CandidateRetirementBoundary(base) as boundary:
                accepted = boundary.retire(
                    {
                        "privateFieldInstall": {"installed": True},
                        "retainedSignedFieldArtifact": {"retained": True},
                        "physicalResultCollected": False,
                    }
                )
                self.assertFalse(accepted["physicalResultCollected"])
                with self.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
                    base.git(Path("/candidate"), "status", "--porcelain=v1")
                with self.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
                    base.git_bytes(Path("/candidate"), "show", "HEAD:A.swift")
                with self.assertRaisesRegex(MODULE.PrivateReviewGoError, "authority retired"):
                    MODULE._physical_blob_oid(Path("/candidate"), "A.swift", b"100644", "0" * 40)
                with self.assertRaises(MODULE._SealedHandoffError):
                    boundary.retire(accepted)
            self.assertIs(base.git, base.original_git)
            self.assertIs(base.git_bytes, base.original_git_bytes)
            self.assertFalse(MODULE._CANDIDATE_RETIRED.get())
        finally:
            MODULE._PREDECESSOR_PHYSICAL_BLOB_OID = original_physical

    def test_build_retires_before_candidate_context_release_and_post_handoff_mutation_is_not_input(self) -> None:
        base = _FakeBase()
        events: list[str] = []
        record = {
            "privateFieldInstall": {"installed": True, "fingerprint": "sealed-install"},
            "retainedSignedFieldArtifact": {"sha256": "sealed-artifact"},
            "physicalResultCollected": False,
        }

        with tempfile.TemporaryDirectory(prefix="nembra-finalgo-sealed-handoff-") as temporary:
            root = Path(temporary)
            tracked = root / "A.swift"
            tracked.write_text("accepted\n", encoding="utf-8")

            @contextlib.contextmanager
            def fake_candidate_custody(_base: object, candidate_repo: Path, source: str):
                self.assertEqual(candidate_repo, root)
                self.assertEqual(source, "a" * 40)
                events.append("custody-enter")
                try:
                    yield
                finally:
                    events.append("custody-release-start")
                    # This is the release-race schedule from #3047/#3048/#3054:
                    # the mutable checkout changes only after the sealed build
                    # result has been produced. It must no longer be an input.
                    tracked.write_text("attacker-after-handoff\n", encoding="utf-8")
                    try:
                        base.git(root, "status", "--porcelain=v1")
                    except MODULE.PrivateReviewGoError:
                        events.append("post-handoff-git-blocked")
                    else:
                        raise AssertionError("candidate Git reopened after sealed handoff")
                    try:
                        MODULE._physical_blob_oid(root, "A.swift", b"100644", "0" * 40)
                    except MODULE.PrivateReviewGoError:
                        events.append("post-handoff-blob-blocked")
                    else:
                        raise AssertionError("candidate blob reopened after sealed handoff")
                    events.append("custody-release-finished")

            @contextlib.contextmanager
            def fake_vnode_authority():
                events.append("vnode-enter")
                try:
                    yield
                finally:
                    events.append("vnode-exit")

            def fake_semantic_build(**kwargs: object):
                self.assertEqual(kwargs["candidate_repo"], root)
                self.assertEqual(kwargs["source"], "a" * 40)
                self.assertIs(kwargs["base_module"], base)
                self.assertEqual(tracked.read_text(encoding="utf-8"), "accepted\n")
                events.append("semantic-build-complete")
                return record

            original_custody = MODULE._PREDECESSOR_CANDIDATE_GIT_CUSTODY
            original_vnode = MODULE._CURRENT_VNODE_AUTHORITY
            original_semantic = MODULE._SEMANTIC_BUILD
            MODULE._PREDECESSOR_CANDIDATE_GIT_CUSTODY = fake_candidate_custody
            MODULE._CURRENT_VNODE_AUTHORITY = fake_vnode_authority
            MODULE._SEMANTIC_BUILD = fake_semantic_build
            try:
                result = MODULE.build(
                    candidate_repo=root,
                    source="A" * 40,
                    base_module=base,
                )
            finally:
                MODULE._PREDECESSOR_CANDIDATE_GIT_CUSTODY = original_custody
                MODULE._CURRENT_VNODE_AUTHORITY = original_vnode
                MODULE._SEMANTIC_BUILD = original_semantic

            self.assertIs(result, record)
            self.assertEqual(tracked.read_text(encoding="utf-8"), "attacker-after-handoff\n")
            self.assertIn("post-handoff-git-blocked", events)
            self.assertIn("post-handoff-blob-blocked", events)
            self.assertLess(events.index("semantic-build-complete"), events.index("custody-release-start"))
            self.assertIs(base.git, base.original_git)
            self.assertIs(base.git_bytes, base.original_git_bytes)

    def test_exact_base_publishes_record_without_reopening_candidate(self) -> None:
        payload = _accepted_blob(BASE_SOURCE, BASE_PATH, BASE_BLOB)
        text = payload.decode("utf-8")
        tree = ast.parse(text)
        build = _function(tree, "build")
        publication = _function(tree, "publication")
        main = _function(tree, "main")

        installer = _call_positions(build, "run_installer")
        inspect_signed = _call_positions(build, "inspect_signed_artifact")
        reinspect_signed = _call_positions(build, "reinspect_signed_artifact")
        candidate = _call_positions(build, "candidate")
        returns = [node for node in ast.walk(build) if isinstance(node, ast.Return)]
        self.assertEqual(len(installer), 1)
        self.assertTrue(inspect_signed)
        self.assertTrue(reinspect_signed)
        self.assertGreaterEqual(len(candidate), 2)
        self.assertEqual(len(returns), 1)
        final_return = returns[0]
        position = (final_return.lineno, final_return.col_offset)
        self.assertLess(installer[0], reinspect_signed[-1])
        self.assertLess(reinspect_signed[-1], position)
        self.assertLess(candidate[-1], position)

        self.assertIsInstance(final_return.value, ast.Dict)
        assert isinstance(final_return.value, ast.Dict)
        keys = {
            key.value
            for key in final_return.value.keys
            if isinstance(key, ast.Constant) and isinstance(key.value, str)
        }
        self.assertTrue(
            {"privateFieldInstall", "retainedSignedFieldArtifact", "physicalResultCollected"}.issubset(keys)
        )

        publication_arguments = [
            argument.arg for argument in publication.args.args + publication.args.kwonlyargs
        ]
        self.assertNotIn("candidate_repo", publication_arguments)
        self.assertNotIn("source", publication_arguments)
        build_calls = _call_positions(main, "build")
        publish_calls = _call_positions(main, "publish_record_no_replace")
        self.assertEqual(len(build_calls), 1)
        self.assertEqual(len(publish_calls), 1)
        self.assertLess(build_calls[0], publish_calls[0])

        publish_node = next(
            node
            for node in ast.walk(main)
            if isinstance(node, ast.Call) and _call_name(node).endswith("publish_record_no_replace")
        )
        referenced = {
            node.id
            for argument in [*publish_node.args, *(item.value for item in publish_node.keywords)]
            for node in ast.walk(argument)
            if isinstance(node, ast.Name)
        }
        self.assertNotIn("candidate_repo", referenced)
        self.assertNotIn("source", referenced)


if __name__ == "__main__":
    unittest.main(verbosity=2)
