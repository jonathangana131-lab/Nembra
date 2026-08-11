#!/usr/bin/env python3
"""Validate the exact Final-GO candidate -> installed/signed-artifact handoff point.

This is validation-only. It does not declare the current watcher release safe.
It proves a narrower architectural premise needed by the production repair: the
current wrapper holds candidate custody around the complete private build, while
all candidate-consuming postchecks and signed-artifact reinspection occur before
the wrapped build returns. After that return the outer wrapper has no candidate
consumer other than custody teardown. A production successor can therefore make
an explicit one-way authority transition at this boundary instead of pretending
a mutable checkout can remain frozen forever.
"""
from __future__ import annotations

import ast
import hashlib
import os
from pathlib import Path
import subprocess
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
PRODUCT_PATH = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
GENERATED_PATH = "scripts/ci/es80_authenticated_stationary_generated_subject_final_go.py"
BASE_PATH = "scripts/ci/es80_authenticated_stationary_final_go.py"

CURRENT_PRODUCT_BLOB = "baef9de23a680bedf16f9f7b367f45f7710ac0c6"
PRIVATE_PARENT_SOURCE = "3c8711f8520b93e2647ec9e3b52d50894193bc30"
PRIVATE_PARENT_BLOB = "c6c0b68ad9c2af7cd3378c721752fbca7d4ed9e9"
GENERATED_PARENT_SOURCE = "b4a2172cd799d363cb503a1ecb3d15bc7382e36f"
GENERATED_PARENT_BLOB = "13720f812498d86f55c0f1ca4e98b873f0793cb9"
BASE_PARENT_SOURCE = "3fdd32551831c3469e0853ddcee8fa828d38b87b"
BASE_PARENT_BLOB = "b0664c734004c2265b05d23ec58756806ff62f2c"


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


def _git(*arguments: str, input_bytes: bytes | None = None) -> bytes:
    return subprocess.run(
        ["/usr/bin/git", "-C", str(REPOSITORY), *arguments],
        input=input_bytes,
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


def _accepted_source(source: str, path: str, expected_blob: str) -> str:
    blob = _git("rev-parse", f"{source}:{path}").decode("ascii").strip().lower()
    if blob != expected_blob:
        raise AssertionError(f"{source}:{path} moved from accepted blob {expected_blob} to {blob}")
    payload = _git("cat-file", "blob", blob)
    if _canonical_blob_oid(payload, blob) != blob:
        raise AssertionError(f"{source}:{path} did not return canonical Git blob bytes")
    return payload.decode("utf-8")


def _current_source(path: str, expected_blob: str) -> str:
    blob = _git("rev-parse", f"HEAD:{path}").decode("ascii").strip().lower()
    if blob != expected_blob:
        raise AssertionError(f"current product path moved from reviewed blob {expected_blob} to {blob}")
    payload = _git("cat-file", "blob", blob)
    if _canonical_blob_oid(payload, blob) != blob:
        raise AssertionError("current product Git blob bytes failed canonical identity")
    return payload.decode("utf-8")


def _function(tree: ast.AST, name: str) -> ast.FunctionDef:
    matches = [node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef) and node.name == name]
    if len(matches) != 1:
        raise AssertionError(f"expected exactly one function named {name}, found {len(matches)}")
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
    positions: list[tuple[int, int]] = []
    for node in ast.walk(function):
        if isinstance(node, ast.Call) and _call_name(node).endswith(suffix):
            positions.append((node.lineno, node.col_offset))
    return sorted(positions)


def _return_positions(function: ast.FunctionDef) -> list[tuple[int, int]]:
    return sorted((node.lineno, node.col_offset) for node in ast.walk(function) if isinstance(node, ast.Return))


def _dict_keys(node: ast.AST) -> set[str]:
    if not isinstance(node, ast.Dict):
        return set()
    result: set[str] = set()
    for key in node.keys:
        if isinstance(key, ast.Constant) and isinstance(key.value, str):
            result.add(key.value)
    return result


class FinalGoSignedArtifactHandoffContractTests(unittest.TestCase):
    def test_current_wrapper_has_no_candidate_consumer_after_wrapped_build(self) -> None:
        text = _current_source(PRODUCT_PATH, CURRENT_PRODUCT_BLOB)
        tree = ast.parse(text)
        build = _function(tree, "build")

        self.assertGreaterEqual(len(build.body), 3)
        final_statement = build.body[-1]
        self.assertIsInstance(final_statement, ast.With)
        assert isinstance(final_statement, ast.With)

        context_names = [
            _call_name(item.context_expr)
            for item in final_statement.items
            if isinstance(item.context_expr, ast.Call)
        ]
        self.assertIn("_candidate_git_custody", context_names)
        self.assertIn("_direct_parent._current_vnode_authority", context_names)
        self.assertEqual(len(final_statement.body), 1)
        result = final_statement.body[0]
        self.assertIsInstance(result, ast.Return)
        assert isinstance(result, ast.Return)
        self.assertIsInstance(result.value, ast.Call)
        assert isinstance(result.value, ast.Call)
        self.assertEqual(_call_name(result.value), "_direct_parent._parent.build")
        keyword_names = {item.arg for item in result.value.keywords if item.arg is not None}
        self.assertIn("candidate_repo", keyword_names)
        self.assertIn("source", keyword_names)

        # Python evaluates the return expression, then exits both contexts,
        # then returns. There is deliberately no statement after this With in
        # the wrapper that could reopen candidate_repo after custody release.
        self.assertIs(build.body[-1], final_statement)

    def test_private_and_generated_layers_finish_candidate_postchecks_before_return(self) -> None:
        private_text = _accepted_source(PRIVATE_PARENT_SOURCE, PRODUCT_PATH, PRIVATE_PARENT_BLOB)
        private_build = _function(ast.parse(private_text), "build")
        private_generated = _call_positions(private_build, "generated.build")
        private_post_candidate = _call_positions(private_build, "candidate_private_authority")
        private_returns = _return_positions(private_build)
        self.assertEqual(len(private_generated), 1)
        self.assertGreaterEqual(len(private_post_candidate), 2)
        self.assertTrue(private_returns)
        self.assertLess(private_generated[0], private_post_candidate[-1])
        self.assertLess(private_post_candidate[-1], private_returns[-1])

        generated_text = _accepted_source(
            GENERATED_PARENT_SOURCE, GENERATED_PATH, GENERATED_PARENT_BLOB
        )
        generated_build = _function(ast.parse(generated_text), "build")
        base_build = _call_positions(generated_build, "base.build")
        generated_post_candidate = _call_positions(generated_build, "candidate_generated_authority")
        generated_returns = _return_positions(generated_build)
        self.assertEqual(len(base_build), 1)
        self.assertGreaterEqual(len(generated_post_candidate), 2)
        self.assertTrue(generated_returns)
        self.assertLess(base_build[0], generated_post_candidate[-1])
        self.assertLess(generated_post_candidate[-1], generated_returns[-1])

    def test_base_build_seals_install_and_retained_artifact_before_return(self) -> None:
        text = _accepted_source(BASE_PARENT_SOURCE, BASE_PATH, BASE_PARENT_BLOB)
        build = _function(ast.parse(text), "build")

        installer = _call_positions(build, "run_installer")
        inspect_signed = _call_positions(build, "inspect_signed_artifact")
        reinspect_signed = _call_positions(build, "reinspect_signed_artifact")
        candidate = _call_positions(build, "candidate")
        returns = [node for node in ast.walk(build) if isinstance(node, ast.Return)]
        self.assertEqual(len(installer), 1)
        self.assertGreaterEqual(len(inspect_signed), 1)
        self.assertGreaterEqual(len(reinspect_signed), 1)
        self.assertGreaterEqual(len(candidate), 2)
        self.assertEqual(len(returns), 1)
        final_return = returns[0]
        return_position = (final_return.lineno, final_return.col_offset)

        self.assertLess(installer[0], inspect_signed[0])
        self.assertLess(inspect_signed[0], reinspect_signed[-1])
        self.assertLess(reinspect_signed[-1], return_position)
        self.assertLess(candidate[-1], return_position)

        keys = _dict_keys(final_return.value)
        self.assertTrue(
            {"privateFieldInstall", "retainedSignedFieldArtifact", "physicalResultCollected"}.issubset(keys),
            "Final-GO base record must carry completed install + retained signed subject before handoff",
        )
        assert isinstance(final_return.value, ast.Dict)
        value_by_key = {
            key.value: value
            for key, value in zip(final_return.value.keys, final_return.value.values)
            if isinstance(key, ast.Constant) and isinstance(key.value, str)
        }
        physical = value_by_key.get("physicalResultCollected")
        self.assertIsInstance(physical, ast.Constant)
        assert isinstance(physical, ast.Constant)
        self.assertIs(physical.value, False)

    def test_publication_after_build_does_not_reopen_candidate_repository(self) -> None:
        text = _accepted_source(BASE_PARENT_SOURCE, BASE_PATH, BASE_PARENT_BLOB)
        tree = ast.parse(text)
        publication = _function(tree, "publication")
        argument_names = [argument.arg for argument in publication.args.args + publication.args.kwonlyargs]
        self.assertNotIn("candidate_repo", argument_names)
        self.assertNotIn("source", argument_names)

        main = _function(tree, "main")
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
