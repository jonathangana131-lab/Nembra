#!/usr/bin/env python3
"""Permanent source/selection contracts for Darwin descriptor ACL rollback."""
from __future__ import annotations

import importlib.util
import inspect
from pathlib import Path
import unittest
from unittest import mock

REPOSITORY = Path(__file__).resolve().parents[3]
ORCHESTRATOR = REPOSITORY / "scripts/ci/capture_selected_xcode_build_orchestrator.py"


def load():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_read_lease_darwin_native", ORCHESTRATOR
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load selected-Xcode build orchestrator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CapturePrivateReadLeaseDarwinNativeTransportTests(unittest.TestCase):
    def test_native_transport_is_root_darwin_only(self) -> None:
        helper = load()
        with (
            mock.patch.object(helper.sys, "platform", "darwin"),
            mock.patch.object(helper.os, "geteuid", return_value=0),
        ):
            self.assertTrue(helper._use_native_darwin_acl())
        with (
            mock.patch.object(helper.sys, "platform", "darwin"),
            mock.patch.object(helper.os, "geteuid", return_value=501),
        ):
            self.assertFalse(helper._use_native_darwin_acl())
        with (
            mock.patch.object(helper.sys, "platform", "linux"),
            mock.patch.object(helper.os, "geteuid", return_value=0),
        ):
            self.assertFalse(helper._use_native_darwin_acl())

    def test_native_restore_distinguishes_absent_and_seeded_baselines(self) -> None:
        helper = load()
        source = inspect.getsource(helper._darwin_acl_restore)
        self.assertIn('baseline["present"]', source)
        self.assertIn("libc.acl_init(0)", source)
        self.assertIn("libc.acl_set_fd(descriptor", source)
        self.assertIn("_darwin_acl_snapshot(descriptor)", source)
        self.assertIn("native ACL baseline was not restored exactly", source)

    def test_grant_uses_canonical_path_but_rollback_uses_held_descriptor(self) -> None:
        helper = load()
        grant = inspect.getsource(helper._PrivateReadLease.grant)
        revoke = inspect.getsource(helper._PrivateReadLease.revoke)
        self.assertIn("_darwin_acl_snapshot(descriptor)", grant)
        self.assertIn('_chmod_path_acl(path, "+a", acl)', grant)
        self.assertIn("_open_pinned_path(path, is_directory, accepted_signature)", grant)
        self.assertIn("_darwin_acl_restore(descriptor, baseline)", revoke)
        self.assertNotIn('_chmod_path_acl(path, "-a"', revoke)
        self.assertIn("pathname no longer identifies opened object", revoke)

    def test_native_baseline_snapshot_is_released_on_every_revoke_path(self) -> None:
        helper = load()
        revoke = inspect.getsource(helper._PrivateReadLease.revoke)
        self.assertIn("_darwin_acl_release(baseline)", revoke)
        self.assertIn('record["darwin_baseline"] = None', revoke)


if __name__ == "__main__":
    unittest.main(verbosity=2)
