#!/usr/bin/env python3
from pathlib import Path

path = Path("Scripts/capture_tuya_private_input_build_guard.py")
text = path.read_text()

anchor = "def _watch_paths(inputs: PrivateInputs) -> tuple[Path, ...]:\n"
helpers = '''def _lexical_absolute(path: Path) -> Path:
    return Path(os.path.abspath(os.fspath(path.expanduser())))


def _require_real_checkout_ancestry(path: Path, root: Path, *, label: str) -> Path:
    candidate = _lexical_absolute(path)
    authority_root = _lexical_absolute(root)
    try:
        relative = candidate.relative_to(authority_root)
    except ValueError as error:
        raise BuildGuardError(f"{label} must remain inside the accepted checkout root") from error
    try:
        root_metadata = authority_root.lstat()
    except OSError as error:
        raise BuildGuardError("accepted checkout root disappeared before build-window custody") from error
    if not stat.S_ISDIR(root_metadata.st_mode) or stat.S_ISLNK(root_metadata.st_mode):
        raise BuildGuardError("accepted checkout root must be one real directory")
    current = authority_root
    for component in relative.parts:
        current = current / component
        try:
            metadata = current.lstat()
        except OSError as error:
            raise BuildGuardError(f"{label} path ancestry disappeared before build-window custody: {current}") from error
        if stat.S_ISLNK(metadata.st_mode):
            raise BuildGuardError(f"{label} path ancestry must not contain symlinks: {current}")
    return candidate


def _add_private_ancestor_watch_paths(paths: set[Path], path: Path, root: Path) -> None:
    current = path.parent
    while current != root:
        if root not in current.parents:
            raise BuildGuardError("private build-input ancestry escaped accepted checkout root")
        paths.add(current)
        current = current.parent


'''
if anchor not in text or "_require_real_checkout_ancestry" in text:
    raise SystemExit("watch-path insertion anchor missing/already transformed")
text = text.replace(anchor, helpers + anchor, 1)

watch_old = '''def _watch_paths(inputs: PrivateInputs) -> tuple[Path, ...]:
    """Return every real file/directory whose mutation can change admitted build inputs."""

    paths: set[Path] = {
        inputs.lockfile,
        inputs.security_podspec,
        inputs.identity_podspec,
    }
'''
watch_new = '''def _watch_paths(inputs: PrivateInputs) -> tuple[Path, ...]:
    """Return every real file/directory whose mutation can change admitted build inputs."""

    root = inputs.lockfile.parent
    private_paths = (
        (inputs.security_podspec, "private security podspec"),
        (inputs.security_build, "private security build tree"),
        (inputs.identity_podspec, "private identity podspec"),
        (inputs.identity_sources, "private identity source tree"),
    )
    for private_path, label in private_paths:
        _require_real_checkout_ancestry(private_path, root, label=label)

    paths: set[Path] = {
        inputs.lockfile,
        inputs.security_podspec,
        inputs.identity_podspec,
    }
    for private_path, _ in private_paths:
        _add_private_ancestor_watch_paths(paths, private_path, root)
'''
if watch_old not in text:
    raise SystemExit("watch-path body anchor missing")
text = text.replace(watch_old, watch_new, 1)

parse_old = '''    lockfile = args.lockfile.resolve()
    root = lockfile.parent
    return (
        PrivateInputs(
            lockfile=lockfile,
            security_podspec=args.security_podspec.resolve(),
            security_build=args.security_build.resolve(),
            identity_podspec=args.identity_podspec.resolve(),
            identity_sources=args.identity_sources.resolve(),
            generated_pods=root / "Pods",
            generated_workspace=root / "NembraCapture.xcworkspace",
        ),
        command,
    )
'''
parse_new = '''    lockfile = _lexical_absolute(args.lockfile)
    root = lockfile.parent
    lockfile = _require_real_checkout_ancestry(lockfile, root, label="dependency lock")
    security_podspec = _require_real_checkout_ancestry(args.security_podspec, root, label="private security podspec")
    security_build = _require_real_checkout_ancestry(args.security_build, root, label="private security build tree")
    identity_podspec = _require_real_checkout_ancestry(args.identity_podspec, root, label="private identity podspec")
    identity_sources = _require_real_checkout_ancestry(args.identity_sources, root, label="private identity source tree")
    return (
        PrivateInputs(
            lockfile=lockfile,
            security_podspec=security_podspec,
            security_build=security_build,
            identity_podspec=identity_podspec,
            identity_sources=identity_sources,
            generated_pods=root / "Pods",
            generated_workspace=root / "NembraCapture.xcworkspace",
        ),
        command,
    )
'''
if parse_old not in text:
    raise SystemExit("parse-args ancestry anchor missing")
text = text.replace(parse_old, parse_new, 1)
path.write_text(text)

# Adapt the already demonstrated expected-red diagnostic to the winning #2709
# generated-subject API/environment while preserving the attack itself.
test = Path("scripts/ci/tests/test_capture_private_input_ancestor_retarget.py")
test.write_text('''#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

REPOSITORY = Path(__file__).resolve().parents[3]
GUARD = REPOSITORY / "Scripts/capture_tuya_private_input_build_guard.py"
SPEC = importlib.util.spec_from_file_location("nembra_private_input_guard_redteam", GUARD)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load Capture field-build guard")
guard = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = guard
SPEC.loader.exec_module(guard)


class QuietBackend:
    def register(self, descriptor: int) -> None:
        del descriptor
    def events(self, timeout: float):
        del timeout
        return []
    def close(self) -> None:
        pass


class CompletedProcess:
    returncode = 0
    def poll(self): return 0
    def terminate(self) -> None: raise AssertionError("completed fake child must not be terminated")
    def wait(self, timeout=None): del timeout; return 0
    def kill(self) -> None: raise AssertionError("completed fake child must not be killed")


class PrivateInputAncestorRetargetTests(unittest.TestCase):
    def test_guard_rejects_private_sdk_ancestor_retarget_before_child_consumption(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-private-input-retarget-") as temporary:
            root = Path(temporary)
            local = root / "LocalSecrets"
            local.mkdir()
            accepted_sdk = root / "accepted-sdk"
            substituted_sdk = root / "substituted-sdk"
            for sdk, payload in ((accepted_sdk, "ACCEPTED"), (substituted_sdk, "SUBSTITUTED")):
                build = sdk / "Build"
                build.mkdir(parents=True)
                (sdk / "ThingSmartCryption.podspec").write_text("Pod::Spec.new do |s|\\nend\\n", encoding="utf-8")
                (build / "payload.bin").write_text(payload, encoding="utf-8")
            sdk_link = local / "TuyaSDK"
            sdk_link.symlink_to(accepted_sdk, target_is_directory=True)
            identity = local / "TuyaRuntime"
            identity_sources = identity / "Sources/NembraTuyaPrivateConfig"
            identity_sources.mkdir(parents=True)
            (identity / "NembraTuyaPrivateConfig.podspec").write_text("Pod::Spec.new do |s|\\nend\\n", encoding="utf-8")
            (identity_sources / "NembraTuyaPrivateIdentity.swift").write_text("enum PrivateIdentity {}\\n", encoding="utf-8")
            lockfile = root / "Podfile.lock"
            lockfile.write_text("PODS:\\n  - Example (1.0)\\n", encoding="utf-8")
            pods = root / "Pods"; workspace = root / "NembraCapture.xcworkspace"
            pods.mkdir(); workspace.mkdir()
            (pods / "generated.xcconfig").write_text("SETTING = ACCEPTED\\n", encoding="utf-8")
            (workspace / "contents.xcworkspacedata").write_text("ACCEPTED\\n", encoding="utf-8")
            accepted_generated = guard.generated_build.build_subject(lockfile=lockfile, pods=pods, workspace=workspace)
            consumed: list[str] = []
            def launch(_command):
                sdk_link.unlink(); sdk_link.symlink_to(substituted_sdk, target_is_directory=True)
                consumed.append((sdk_link / "Build/payload.bin").read_text(encoding="utf-8"))
                return CompletedProcess()
            argv = ["--lockfile",str(lockfile),"--security-podspec",str(sdk_link / "ThingSmartCryption.podspec"),"--security-build",str(sdk_link / "Build"),"--identity-podspec",str(identity / "NembraTuyaPrivateConfig.podspec"),"--identity-sources",str(identity_sources),"--","fake-xcodebuild"]
            def attempt() -> None:
                with patch.dict(os.environ,{"NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256":accepted_generated},clear=False):
                    inputs, command = guard._parse_args(argv)
                    guard.run_guarded_build(inputs,command,backend_factory=QuietBackend,popen_factory=launch,poll_interval=0.0,require_accepted_generated_subject=True)
            with self.assertRaises(guard.BuildGuardError):
                attempt()
            self.assertEqual(consumed, [], "substituted private SDK bytes reached the fake build")


if __name__ == "__main__":
    unittest.main(verbosity=2)
''')

workflow = Path(".github/workflows/capture-cocoapods-build-subject-redteam.yml")
w = workflow.read_text()
path_anchor = "      - scripts/ci/tests/test_capture_cocoapods_generated_symlink_authority.py\n"
if path_anchor not in w or "test_capture_private_input_ancestor_retarget.py" in w:
    raise SystemExit("workflow path anchor missing/already transformed")
w = w.replace(path_anchor, path_anchor + "      - scripts/ci/tests/test_capture_private_input_ancestor_retarget.py\n", 1)
compile_anchor = "          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_cocoapods_generated_symlink_authority.py\n"
w = w.replace(compile_anchor, compile_anchor + "          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_input_ancestor_retarget.py\n", 1)
step_anchor = "      - name: Require generated symlinks to stay inside accepted authority\n        shell: bash\n        run: |\n          set -euo pipefail\n          /usr/bin/python3 scripts/ci/tests/test_capture_cocoapods_generated_symlink_authority.py\n"
if step_anchor not in w:
    raise SystemExit("workflow test-step anchor missing")
w = w.replace(step_anchor, step_anchor + "\n      - name: Require private build-input ancestry to remain pinned\n        shell: bash\n        run: |\n          set -euo pipefail\n          /usr/bin/python3 scripts/ci/tests/test_capture_private_input_ancestor_retarget.py\n", 1)
workflow.write_text(w)
