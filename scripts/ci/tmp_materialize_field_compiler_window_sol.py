#!/usr/bin/env python3
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


guard_path = Path("Scripts/capture_tuya_private_input_build_guard.py")
installer_path = Path("scripts/field/install_one_time_capture.command")
provenance_test_path = Path("scripts/ci/tests/test_capture_tuya_private_input_provenance.py")
provenance_workflow_path = Path(".github/workflows/capture-field-build-provenance.yml")
workflow_path = Path(".github/workflows/tmp-v14-capture-field-compiler-window-sol.yml")
script_path = Path("scripts/ci/tmp_materialize_field_compiler_window_sol.py")

guard = guard_path.read_text(encoding="utf-8")
installer = installer_path.read_text(encoding="utf-8")
provenance_test = provenance_test_path.read_text(encoding="utf-8")
provenance_workflow = provenance_workflow_path.read_text(encoding="utf-8")

guard = replace_once(
    guard,
    "    generated_pods: Path | None = None\n    generated_workspace: Path | None = None\n",
    "    generated_pods: Path | None = None\n    generated_workspace: Path | None = None\n    accepted_source_root: Path | None = None\n    accepted_source_sha: str | None = None\n",
    "PrivateInputs accepted-source fields",
)

accepted_source_helpers = r'''

def _accepted_source_git_environment(root: Path) -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_DIR": str(root / ".git"),
        "GIT_WORK_TREE": str(root),
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_COUNT": "5",
        "GIT_CONFIG_KEY_0": "core.worktree",
        "GIT_CONFIG_VALUE_0": str(root),
        "GIT_CONFIG_KEY_1": "core.bare",
        "GIT_CONFIG_VALUE_1": "false",
        "GIT_CONFIG_KEY_2": "core.fsmonitor",
        "GIT_CONFIG_VALUE_2": "false",
        "GIT_CONFIG_KEY_3": "core.ignorestat",
        "GIT_CONFIG_VALUE_3": "false",
        "GIT_CONFIG_KEY_4": "core.filemode",
        "GIT_CONFIG_VALUE_4": "true",
    }


def _accepted_source_manifest(inputs: PrivateInputs) -> dict[Path, tuple[str, bool]]:
    """Read and verify the exact accepted tracked tree without checkout index/config trust."""

    if inputs.accepted_source_root is None and inputs.accepted_source_sha is None:
        return {}
    if inputs.accepted_source_root is None or inputs.accepted_source_sha is None:
        raise BuildGuardError("accepted tracked-source custody requires both checkout root and source SHA")

    root = _lexical_absolute(inputs.accepted_source_root)
    if root != _lexical_absolute(inputs.lockfile.parent):
        raise BuildGuardError("accepted tracked-source root must equal the field checkout root")
    try:
        root_metadata = root.lstat()
        git_metadata = (root / ".git").lstat()
    except OSError as error:
        raise BuildGuardError("accepted tracked-source checkout authority disappeared before build-window custody") from error
    if not stat.S_ISDIR(root_metadata.st_mode) or stat.S_ISLNK(root_metadata.st_mode):
        raise BuildGuardError("accepted tracked-source root must be one real directory")
    if not stat.S_ISDIR(git_metadata.st_mode) or stat.S_ISLNK(git_metadata.st_mode):
        raise BuildGuardError("accepted tracked-source Git authority must be one real .git directory")

    source_sha = inputs.accepted_source_sha.lower()
    if len(source_sha) != 40 or any(character not in "0123456789abcdef" for character in source_sha):
        raise BuildGuardError("accepted tracked-source SHA must be exactly 40 hexadecimal characters")

    git_environment = _accepted_source_git_environment(root)
    try:
        current = subprocess.check_output(
            ["/usr/bin/git", "rev-parse", "--verify", "HEAD^{commit}"],
            cwd=root,
            env=git_environment,
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip().lower()
        tree = subprocess.check_output(
            ["/usr/bin/git", "ls-tree", "-r", "-z", source_sha],
            cwd=root,
            env=git_environment,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise BuildGuardError("accepted tracked-source Git tree could not be read from exact authority") from error
    if current != source_sha:
        raise BuildGuardError("accepted tracked-source checkout HEAD no longer matches the externally accepted SHA")

    manifest: dict[Path, tuple[str, bool]] = {}
    for record in tree.split(b"\0"):
        if not record:
            continue
        try:
            header, raw_path = record.split(b"\t", 1)
            raw_mode, raw_type, raw_oid = header.split(b" ", 2)
            mode = raw_mode.decode("ascii")
            object_type = raw_type.decode("ascii")
            oid = raw_oid.decode("ascii").lower()
        except (ValueError, UnicodeDecodeError) as error:
            raise BuildGuardError("accepted tracked-source Git tree contains a malformed entry") from error
        if object_type != "blob" or mode not in {"100644", "100755"}:
            raise BuildGuardError(
                f"accepted tracked-source entry has unsupported type/mode: {object_type} {mode}"
            )
        if len(oid) != 40 or any(character not in "0123456789abcdef" for character in oid):
            raise BuildGuardError("accepted tracked-source Git blob identity is malformed")
        relative = Path(os.fsdecode(raw_path))
        if relative.is_absolute() or not relative.parts or ".." in relative.parts or "." in relative.parts:
            raise BuildGuardError("accepted tracked-source Git path escapes the checkout root")
        path = root / relative
        try:
            metadata = path.lstat()
        except OSError as error:
            raise BuildGuardError(f"accepted tracked source disappeared before custody: {relative}") from error
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise BuildGuardError(f"accepted tracked source must be one real regular file: {relative}")
        expected_executable = mode == "100755"
        if bool(stat.S_IMODE(metadata.st_mode) & 0o111) != expected_executable:
            raise BuildGuardError(f"accepted tracked source executable mode differs from Git authority: {relative}")
        if path in manifest:
            raise BuildGuardError(f"accepted tracked-source Git path is duplicated: {relative}")
        manifest[path] = (oid, expected_executable)
    if not manifest:
        raise BuildGuardError("accepted tracked-source Git tree is empty")
    return manifest


def _verify_accepted_tracked_source_descriptors(
    manifest: dict[Path, tuple[str, bool]],
    watched: Sequence[tuple[int, Path]],
) -> None:
    """Bind watched checkout files to accepted Git blobs before/after compiler use."""

    if not manifest:
        return
    descriptors = {path: descriptor for descriptor, path in watched}
    for path, (expected_oid, expected_executable) in manifest.items():
        descriptor = descriptors.get(path)
        if descriptor is None:
            raise BuildGuardError(f"accepted tracked source is not under descriptor custody: {path}")
        try:
            before = os.fstat(descriptor)
            path_before = path.lstat()
        except OSError as error:
            raise BuildGuardError(f"accepted tracked source disappeared during descriptor custody: {path}") from error
        if _stat_identity(before) != _stat_identity(path_before):
            raise BuildGuardError(f"accepted tracked source path retargeted after descriptor admission: {path}")
        if not stat.S_ISREG(before.st_mode):
            raise BuildGuardError(f"accepted tracked source is not one regular file: {path}")
        if bool(stat.S_IMODE(before.st_mode) & 0o111) != expected_executable:
            raise BuildGuardError(f"accepted tracked source executable mode differs from exact Git authority: {path}")

        digest = hashlib.sha1()
        digest.update(b"blob " + str(before.st_size).encode("ascii") + b"\0")
        offset = 0
        while offset < before.st_size:
            try:
                chunk = os.pread(descriptor, min(65_536, before.st_size - offset), offset)
            except OSError as error:
                raise BuildGuardError(f"accepted tracked source could not be read under descriptor custody: {path}") from error
            if not chunk:
                raise BuildGuardError(f"accepted tracked source changed during descriptor read: {path}")
            digest.update(chunk)
            offset += len(chunk)

        try:
            after = os.fstat(descriptor)
            path_after = path.lstat()
        except OSError as error:
            raise BuildGuardError(f"accepted tracked source disappeared after descriptor read: {path}") from error
        if _stat_identity(before) != _stat_identity(after) or _stat_identity(after) != _stat_identity(path_after):
            raise BuildGuardError(f"accepted tracked source changed during descriptor verification: {path}")
        if not hmac.compare_digest(digest.hexdigest(), expected_oid):
            raise BuildGuardError(f"accepted tracked source bytes differ from exact Git authority: {path}")
'''

guard = replace_once(
    guard,
    "\ndef _watch_paths(inputs: PrivateInputs) -> tuple[Path, ...]:\n",
    accepted_source_helpers + "\n\ndef _watch_paths(inputs: PrivateInputs) -> tuple[Path, ...]:\n",
    "accepted-source helper insertion",
)

guard = replace_once(
    guard,
    '    _add_tree_watch_paths(paths, inputs.identity_sources, label="private identity source tree")\n\n    # The parent-chain contract',
    '    _add_tree_watch_paths(paths, inputs.identity_sources, label="private identity source tree")\n\n    accepted_manifest = _accepted_source_manifest(inputs)\n    if accepted_manifest:\n        accepted_source_root = _lexical_absolute(inputs.accepted_source_root)  # type: ignore[arg-type]\n        paths.add(accepted_source_root)\n        for tracked_path in accepted_manifest:\n            paths.add(tracked_path)\n            _add_parent_watch_chain(paths, tracked_path, repository_root=accepted_source_root)\n\n    # The parent-chain contract',
    "tracked-source watch-set expansion",
)
guard = replace_once(
    guard,
    "    initial_snapshot = inputs.generation_snapshot()\n    watch_paths = _watch_paths(inputs)\n",
    "    initial_snapshot = inputs.generation_snapshot()\n    accepted_source_manifest = _accepted_source_manifest(inputs)\n    watch_paths = _watch_paths(inputs)\n",
    "tracked-source manifest capture",
)
guard = replace_once(
    guard,
    "        watched = _open_watched_inputs(watch_paths, backend)\n\n        armed_snapshot = inputs.generation_snapshot()\n",
    "        watched = _open_watched_inputs(watch_paths, backend)\n        _verify_accepted_tracked_source_descriptors(accepted_source_manifest, watched)\n\n        armed_snapshot = inputs.generation_snapshot()\n",
    "pre-build tracked descriptor verification",
)
guard = replace_once(
    guard,
    '        final_snapshot = inputs.generation_snapshot()\n        if final_snapshot != initial_snapshot:\n            raise BuildGuardError("build inputs changed across the guarded xcodebuild window")\n',
    '        final_snapshot = inputs.generation_snapshot()\n        if final_snapshot != initial_snapshot:\n            raise BuildGuardError("build inputs changed across the guarded xcodebuild window")\n        _verify_accepted_tracked_source_descriptors(accepted_source_manifest, watched)\n',
    "post-build tracked descriptor verification",
)
guard = replace_once(
    guard,
    '    parser.add_argument("--identity-sources", required=True, type=Path)\n    parser.add_argument("command", nargs=argparse.REMAINDER)\n',
    '    parser.add_argument("--identity-sources", required=True, type=Path)\n    parser.add_argument("--accepted-source-root", required=True, type=Path)\n    parser.add_argument("--accepted-source-sha", required=True)\n    parser.add_argument("command", nargs=argparse.REMAINDER)\n',
    "accepted-source CLI arguments",
)
guard = replace_once(
    guard,
    '            generated_pods=root / "Pods",\n            generated_workspace=root / "NembraCapture.xcworkspace",\n',
    '            generated_pods=root / "Pods",\n            generated_workspace=root / "NembraCapture.xcworkspace",\n            accepted_source_root=_lexical_absolute(args.accepted_source_root),\n            accepted_source_sha=args.accepted_source_sha,\n',
    "accepted-source PrivateInputs construction",
)

installer = replace_once(
    installer,
    '''PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"
[[ -f "$PRIVATE_DEVICE_RUNNER" ]] || die "Private intended-device reader is missing from the accepted source."
if ! DEVICE_UDID="$(/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT" <<'PY'
import hashlib
import hmac
import importlib.util
import os
import re
import sys
from pathlib import Path

runner_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("nembra_private_device_reader", runner_path)
if spec is None or spec.loader is None:
    raise RuntimeError("private intended-device reader could not be loaded")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
value = module.read_private_identifier(Path(sys.argv[2]), Path(sys.argv[3]))
''',
    '''PRIVATE_DEVICE_RUNNER_RELATIVE="scripts/ci/es80_signed_field_artifact_private_runner.py"
PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB="$(run_authority_git rev-parse "$SOURCE_SHA:$PRIVATE_DEVICE_RUNNER_RELATIVE" 2>/dev/null)" || \
    die "Private intended-device reader is missing from the exact accepted Git tree."
[[ "$PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB" =~ ^[0-9a-f]{40}$ ]] || die "Private intended-device reader Git blob identity is malformed."
PRIVATE_DEVICE_RUNNER="$(run_authority_git cat-file blob "$PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')" || \
    die "Could not capture the private intended-device reader from exact Git authority."
[[ -n "$PRIVATE_DEVICE_RUNNER" ]] || die "Captured private intended-device reader is empty."
[[ "$(printf '%s' "$PRIVATE_DEVICE_RUNNER" | /usr/bin/base64 -D | run_authority_git hash-object --stdin)" == "$PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB" ]] || \
    die "Decoded private intended-device reader bytes do not match the accepted Git blob."
if ! DEVICE_UDID="$(/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT" <<'PY'
import base64
import hashlib
import hmac
import os
import re
import sys
from pathlib import Path

runner_source = base64.b64decode(sys.argv[1], validate=True)
runner_namespace = {
    "__name__": "nembra_private_device_reader",
    "__file__": "<accepted-private-device-runner>",
}
exec(
    compile(runner_source, "<accepted-private-device-runner>", "exec", dont_inherit=True),
    runner_namespace,
)
reader = runner_namespace.get("read_private_identifier")
if not callable(reader):
    raise RuntimeError("accepted private intended-device reader does not expose read_private_identifier")
value = reader(Path(sys.argv[2]), Path(sys.argv[3]))
''',
    "private-device runner accepted-byte execution",
)
installer = replace_once(
    installer,
    'unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 || true\nsay "Private intended-device admission validated against Final GO digest"',
    'unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 PRIVATE_DEVICE_RUNNER PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB PRIVATE_DEVICE_RUNNER_RELATIVE || true\nsay "Private intended-device admission validated against Final GO digest"',
    "private-device runner cleanup",
)
installer = replace_once(
    installer,
    '    --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \\\n    -- /usr/bin/xcodebuild \\\n',
    '    --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \\\n    --accepted-source-root "$ROOT" \\\n    --accepted-source-sha "$SOURCE_SHA" \\\n    -- /usr/bin/xcodebuild \\\n',
    "field installer accepted-source custody arguments",
)

provenance_test = replace_once(
    provenance_test,
    '        bootstrap_call = \'"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"\'\n        build_call = "-- xcodebuild"\n',
    '        secure_bootstrap_call = \'run_accepted_source_bash "Scripts/bootstrap_capture_tuya_sdk.sh"\'\n        retired_bootstrap_call = \'"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"\'\n        accepted_source_read = \'run_authority_git show "$SOURCE_SHA:$relative_path"\'\n        hardened_bash = "/bin/bash --noprofile --norc -p -c \'source /dev/stdin\' \\\"$ROOT/$relative_path\\\""\n        build_call = "-- /usr/bin/xcodebuild"\n',
    "provenance test bootstrap markers",
)
provenance_test = replace_once(
    provenance_test,
    '        self.assertIn(bootstrap_call, installer)\n        self.assertIn(build_call, installer)\n        self.assertLess(installer.index(bootstrap_call), installer.index(build_call))\n',
    '        self.assertIn(secure_bootstrap_call, installer)\n        self.assertIn(accepted_source_read, installer)\n        self.assertIn(hardened_bash, installer)\n        self.assertNotIn(retired_bootstrap_call, installer)\n        self.assertIn(build_call, installer)\n        self.assertLess(installer.index(secure_bootstrap_call), installer.index(build_call))\n',
    "provenance test assertions",
)

provenance_workflow = replace_once(
    provenance_workflow,
    "          grep -Fq 'SOURCE_SHA=\"$(git rev-parse HEAD | tr ' \"$installer\"\n",
    "          grep -Fq 'AUTHORITY_GIT_DIR=\"$ROOT/.git\"' \"$installer\"\n          grep -Fq 'SOURCE_SHA=\"$(run_authority_git rev-parse --verify ' \"$installer\"\n          if grep -Fq 'SOURCE_SHA=\"$(git rev-parse HEAD | tr ' \"$installer\"; then\n            echo 'ERROR: field source authority regressed to ambient Git execution.' >&2\n            exit 1\n          fi\n",
    "field provenance source-SHA authority contract",
)

guard_path.write_text(guard, encoding="utf-8")
installer_path.write_text(installer, encoding="utf-8")
provenance_test_path.write_text(provenance_test, encoding="utf-8")
provenance_workflow_path.write_text(provenance_workflow, encoding="utf-8")
workflow_path.unlink()
script_path.unlink()
