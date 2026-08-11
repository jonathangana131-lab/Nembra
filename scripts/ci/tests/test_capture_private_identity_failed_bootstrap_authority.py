#!/usr/bin/env python3
"""A failed private publication must never become later CocoaPods build input.

This is the accepted counterpart to expected-red #2961. It exercises the real
private writer, leaves attacker-controlled Swift bytes at the canonical identity
path after fail-closed publication, then invokes the real bootstrap from a
fixture containing the accepted authority verifier. CocoaPods must remain
unreached because no root-sealed successful transaction exists for the fixture.
"""

from __future__ import annotations

import ast
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
WRITER_PATH = ROOT / "Scripts/provision_capture_tuya_identity_writer.py"
BOOTSTRAP_PATH = ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh"
AUTHORITY_PATH = ROOT / "Scripts/capture_tuya_private_identity_authority.py"
PROVENANCE_PATH = ROOT / "Scripts/capture_tuya_private_input_provenance.py"
RESOLUTION_GUARD_PATH = ROOT / "Scripts/capture_tuya_private_dependency_resolution_guard.py"
BUILD_GUARD_PATH = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"


def load_writer():
    spec = importlib.util.spec_from_file_location("nembra_failed_bootstrap_writer", WRITER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("private identity writer import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_resolution_adapter():
    spec = importlib.util.spec_from_file_location(
        "nembra_private_dependency_resolution_adapter_test",
        RESOLUTION_GUARD_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("private dependency-resolution adapter import unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FailedPrivateIdentityBootstrapAuthorityTests(unittest.TestCase):
    def test_authority_verification_precedes_cocoapods_discovery(self) -> None:
        source = BOOTSTRAP_PATH.read_text(encoding="utf-8")
        verify = source.index('verify "$REPO_ROOT" "$PRIVATE_IDENTITY_WRITER_SHA256"')
        pod_discovery = source.index("command -v pod")
        self.assertLess(verify, pod_discovery)
        self.assertIn(
            'PRIVATE_IDENTITY_AUTHORITY_HELPER_SHA256="40f5aee5c5e39c0a6146ba2ca7bc6bad7cf6abd6576fff8835d02f714589ae71"',
            source,
        )

    def test_dependency_resolution_and_snapshot_are_vnode_guarded(self) -> None:
        source = BOOTSTRAP_PATH.read_text(encoding="utf-8")
        guard_call = '/usr/bin/python3 -I "$PRIVATE_INPUT_RESOLUTION_GUARD"'
        first_guard = source.index(guard_call)
        second_guard = source.index(guard_call, first_guard + 1)
        pod_exec = source.index('"$POD_BIN" install --repo-update')
        snapshot_exec = source.index('/usr/bin/python3 -I "$PROVENANCE_HELPER" snapshot')

        self.assertLess(first_guard, pod_exec)
        self.assertLess(pod_exec, second_guard)
        self.assertLess(second_guard, snapshot_exec)
        self.assertEqual(source.count(guard_call), 2)
        self.assertIn('--lockfile "$REPO_ROOT/Podfile"', source)
        self.assertIn('verify "$REPO_ROOT_INNER" "$WRITER_SHA_INNER"', source)
        self.assertNotIn("\npod install --repo-update\n", source)

    def test_dependency_resolution_adapter_matches_canonical_guard_api(self) -> None:
        adapter_tree = ast.parse(RESOLUTION_GUARD_PATH.read_text(encoding="utf-8"))
        guard_tree = ast.parse(BUILD_GUARD_PATH.read_text(encoding="utf-8"))

        guard_definitions = [
            node
            for node in guard_tree.body
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            and node.name == "run_guarded_build"
        ]
        self.assertEqual(len(guard_definitions), 1, "canonical run_guarded_build definition is ambiguous")
        guard_definition = guard_definitions[0]
        accepted_parameters = {
            argument.arg
            for argument in (
                list(guard_definition.args.posonlyargs)
                + list(guard_definition.args.args)
                + list(guard_definition.args.kwonlyargs)
            )
        }

        adapter_calls = [
            node
            for node in ast.walk(adapter_tree)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and node.func.attr == "run_guarded_build"
        ]
        self.assertEqual(len(adapter_calls), 1, "dependency adapter must have one canonical guard call")
        supplied_keywords = {
            keyword.arg for keyword in adapter_calls[0].keywords if keyword.arg is not None
        }
        unexpected = supplied_keywords - accepted_parameters
        self.assertFalse(
            unexpected,
            f"dependency adapter passes unsupported canonical guard keywords: {sorted(unexpected)}",
        )
        self.assertFalse(
            any(name.startswith("require_accepted_") for name in supplied_keywords),
            "pre-generated dependency resolution must not fabricate disable-acceptance toggles",
        )

        canonical_members = {
            node.name
            for node in guard_tree.body
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
        }
        adapter_guard_members = {
            node.attr
            for node in ast.walk(adapter_tree)
            if isinstance(node, ast.Attribute)
            and isinstance(node.value, ast.Name)
            and node.value.id == "guard"
        }
        missing_members = adapter_guard_members - canonical_members
        self.assertFalse(
            missing_members,
            f"dependency adapter references nonexistent canonical guard members: {sorted(missing_members)}",
        )
        self.assertNotIn("_lexical_absolute", adapter_guard_members)
        self.assertNotIn("_require_real_checkout_ancestry", adapter_guard_members)

    def test_dependency_resolution_adapter_rejects_escaping_and_symlinked_ancestry(self) -> None:
        adapter = load_resolution_adapter()
        with tempfile.TemporaryDirectory(prefix="nembra-private-resolution-ancestry-") as temporary:
            sandbox = Path(temporary)
            checkout = sandbox / "repo"
            private = checkout / "LocalSecrets" / "TuyaSDK"
            private.mkdir(parents=True)
            podspec = private / "ThingSmartCryption.podspec"
            podspec.write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")

            admitted = adapter._require_real_checkout_ancestry(
                podspec,
                checkout,
                label="private security podspec",
            )
            self.assertEqual(admitted, podspec)

            outside = sandbox / "outside.podspec"
            outside.write_text("outside\n", encoding="utf-8")
            with self.assertRaises(adapter.ResolutionGuardError):
                adapter._require_real_checkout_ancestry(
                    outside,
                    checkout,
                    label="private security podspec",
                )

            real_tree = checkout / "real-build"
            real_tree.mkdir()
            alias = checkout / "aliased-build"
            alias.symlink_to(real_tree, target_is_directory=True)
            with self.assertRaises(adapter.ResolutionGuardError):
                adapter._require_real_checkout_ancestry(
                    alias,
                    checkout,
                    label="private security build tree",
                )

            intermediate = checkout / "alias-parent"
            intermediate.symlink_to(private, target_is_directory=True)
            with self.assertRaises(adapter.ResolutionGuardError):
                adapter._require_real_checkout_ancestry(
                    intermediate / podspec.name,
                    checkout,
                    label="private security podspec",
                )

    def test_failed_publication_attacker_source_is_blocked_before_pod(self) -> None:
        writer = load_writer()
        with tempfile.TemporaryDirectory(prefix="nembra-private-failed-bootstrap-") as temporary:
            repo = Path(temporary) / "repo"
            scripts = repo / "Scripts"
            scripts.mkdir(parents=True, mode=0o700)
            for source in (BOOTSTRAP_PATH, AUTHORITY_PATH, PROVENANCE_PATH, WRITER_PATH):
                shutil.copy2(source, scripts / source.name)

            (repo / "Podfile").write_text("# sentinel Podfile\n", encoding="utf-8")
            (repo / "NembraCapture.xcodeproj").mkdir()

            checkout_fd = os.open(repo, writer._directory_flags())
            original_secure_replace = writer._secure_replace_beneath
            attacker_bytes = (
                b"import Foundation\n"
                b"public enum NembraTuyaPrivateIdentity {\n"
                b"  public static let appKey = \"attacker-key\"\n"
                b"  public static let appSecret = \"attacker-secret\"\n"
                b"}\n"
            )
            attacked = False

            def fail_second_publication(root_fd: int, source_name: str, destination_relative: str, sealed) -> None:
                nonlocal attacked
                if destination_relative.endswith("NembraTuyaPrivateIdentity.swift"):
                    attacked = True
                    os.rename(
                        source_name,
                        f"{source_name}.accepted-held",
                        src_dir_fd=root_fd,
                        dst_dir_fd=root_fd,
                    )
                    parent = repo / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig"
                    canonical = parent / "NembraTuyaPrivateIdentity.swift"
                    canonical.write_bytes(attacker_bytes)
                    canonical.chmod(0o600)
                original_secure_replace(root_fd, source_name, destination_relative, sealed)

            writer._secure_replace_beneath = fail_second_publication
            try:
                with self.assertRaises((writer.ProvisionError, OSError)):
                    writer.provision(
                        checkout_fd,
                        repo,
                        "bmVtYnJhLWR1bW15LWFwcC1rZXk=",
                        "bmVtYnJhLWR1bW15LWFwcC1zZWNyZXQ=",
                    )
            finally:
                writer._secure_replace_beneath = original_secure_replace
                os.close(checkout_fd)

            self.assertTrue(attacked, "fixture never injected the failed second publication")
            canonical = repo / "LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift"
            self.assertEqual(canonical.read_bytes(), attacker_bytes)

            fake_bin = Path(temporary) / "bin"
            fake_bin.mkdir()
            sentinel = Path(temporary) / "pod-invoked"
            fake_pod = fake_bin / "pod"
            fake_pod.write_text(
                "#!/bin/sh\n/bin/echo invoked > \"$NEMBRA_POD_SENTINEL\"\nexit 86\n",
                encoding="utf-8",
            )
            fake_pod.chmod(0o700)

            environment = os.environ.copy()
            environment["PATH"] = f"{fake_bin}:{environment.get('PATH', '')}"
            environment["NEMBRA_POD_SENTINEL"] = str(sentinel)
            environment["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = "a" * 64
            result = subprocess.run(
                ["/bin/bash", str(scripts / "bootstrap_capture_tuya_sdk.sh")],
                cwd=repo,
                env=environment,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=20,
                check=False,
            )

            self.assertEqual(result.returncode, 17, result.stdout)
            self.assertFalse(sentinel.exists(), "bootstrap reached CocoaPods with failed-publication identity bytes")
            self.assertIn("root-sealed last successful provisioning transaction", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
