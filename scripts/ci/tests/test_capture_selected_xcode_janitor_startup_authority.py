#!/usr/bin/env python3
"""Expected-red authority checks for the selected-Xcode root janitor handoff.

This validation does not change production. It demonstrates the POSIX fork
inheritance primitive and requires production to prove a child READY boundary
and explicit closure of inherited non-stdio descriptors before the long-lived
root janitor is promoted.
"""

from __future__ import annotations

import ast
import os
from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parents[3]
PRODUCTION = REPO_ROOT / "scripts/ci/capture_selected_xcode_freeze.py"


def _function_source(name: str) -> str:
    source = PRODUCTION.read_text(encoding="utf-8")
    tree = ast.parse(source, filename=str(PRODUCTION))
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == name:
            segment = ast.get_source_segment(source, node)
            if segment is None:
                raise AssertionError(f"could not recover source for {name}")
            return segment
    raise AssertionError(f"production helper is missing {name}")


class SelectedXcodeJanitorStartupAuthorityTests(unittest.TestCase):
    def test_fork_inherits_nonstdio_descriptor_without_explicit_close(self) -> None:
        if not hasattr(os, "fork"):
            self.skipTest("POSIX fork witness requires os.fork")
        read_fd, write_fd = os.pipe()
        try:
            self.assertGreater(write_fd, 2)
            child = os.fork()
            if child == 0:
                try:
                    os.close(read_fd)
                    os.write(write_fd, b"inherited-root-channel")
                finally:
                    os._exit(0)
            os.close(write_fd)
            write_fd = -1
            payload = os.read(read_fd, 64)
            _, status = os.waitpid(child, 0)
            self.assertTrue(os.WIFEXITED(status))
            self.assertEqual(os.WEXITSTATUS(status), 0)
            self.assertEqual(payload, b"inherited-root-channel")
        finally:
            if read_fd >= 0:
                os.close(read_fd)
            if write_fd >= 0:
                os.close(write_fd)

    def test_production_requires_child_ready_handshake_before_parent_return(self) -> None:
        source = _function_source("_start_cleanup_janitor")
        channel_matches = [
            match.start()
            for pattern in (
                r"\bos\.pipe2?\s*\(",
                r"\bsocket\.socketpair\s*\(",
            )
            for match in re.finditer(pattern, source)
        ]
        self.assertTrue(
            channel_matches,
            "root janitor has no child-to-parent readiness channel; parent can promote a dead/uninitialized child",
        )
        readiness_matches = [
            match.start()
            for pattern in (
                r"\bos\.read\s*\(",
                r"\bselect\.(?:select|poll|kqueue)\b",
                r"\.recv\s*\(",
            )
            for match in re.finditer(pattern, source)
        ]
        self.assertTrue(
            readiness_matches,
            "parent never waits for a child READY/error result before accepting the janitor",
        )
        parent_return = source.find("return child")
        self.assertGreaterEqual(parent_return, 0, "janitor parent return is not auditable")
        self.assertLess(
            min(readiness_matches),
            parent_return,
            "janitor parent returns the child PID before consuming readiness evidence",
        )

    def test_production_closes_inherited_nonstdio_descriptors_before_monitor_loop(self) -> None:
        source = _function_source("_start_cleanup_janitor")
        closes_range = bool(re.search(r"\bos\.(?:closerange|close_range)\s*\(", source))
        enumerates_fd_table = "/dev/fd" in source or "/proc/self/fd" in source
        explicit_descriptor_loop = bool(
            re.search(
                r"for\s+\w+\s+in\s+range\s*\([^\n]+\).*?os\.close\s*\(",
                source,
                re.DOTALL,
            )
        )
        self.assertTrue(
            closes_range or enumerates_fd_table or explicit_descriptor_loop,
            "forked uid-0 janitor closes only stdio; inherited fd>=3 authority is not mechanically removed",
        )


if __name__ == "__main__":
    unittest.main()
