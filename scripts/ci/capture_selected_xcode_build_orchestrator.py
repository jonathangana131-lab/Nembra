#!/usr/bin/env python3
"""Compose selected-Xcode custody with signed Capture build-origin custody.

This root-only helper is executed from exact accepted Git-object bytes by the field
installer. It keeps the selected-Xcode freeze and the dedicated-UID/APFS build in one
privileged process: the freeze launcher first revokes reusable field-user sudo authority,
then this helper substitutes only the launcher-returned frozen xcodebuild into the guarded
build command and calls the accepted build-origin helper directly.

The accepted freeze must also expose exact xctrace/devicectl subjects inside the same
root/no-write Developer tree. They are validated here even though the current installer ABI
continues to return only the protected stage and fingerprint; later device-tool migration
must re-earn its own exact-head boundary rather than smuggling new parent-shell authority
through this build result.

The helper does not discover/install/launch a device, open Bluetooth, interpret Tuya
traffic, or create physical authority. Accepted-source/private-input and Apple signing
boundaries remain independent gates.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
from pathlib import Path
import re
import sys
from typing import Callable, Sequence


class SelectedXcodeBuildOrchestratorError(RuntimeError):
    pass


def _git_blob_oid(raw: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()


def _decode_verified_git_blob(encoded: str, expected_blob: str, label: str) -> bytes:
    if re.fullmatch(r"[0-9a-f]{40}", expected_blob) is None:
        raise SelectedXcodeBuildOrchestratorError(f"{label} expected Git blob identity is malformed")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except Exception as error:
        raise SelectedXcodeBuildOrchestratorError(f"{label} transport is not strict base64") from error
    if _git_blob_oid(raw) != expected_blob:
        raise SelectedXcodeBuildOrchestratorError(f"{label} bytes do not match the accepted Git blob")
    return raw


def _load_namespace(raw: bytes, *, name: str, filename: str) -> dict[str, object]:
    namespace: dict[str, object] = {"__name__": name, "__file__": filename}
    try:
        exec(compile(raw, filename, "exec", dont_inherit=True), namespace)
    except Exception as error:
        raise SelectedXcodeBuildOrchestratorError(f"{name} could not be loaded") from error
    return namespace


def _require_callable(namespace: dict[str, object], name: str, label: str) -> Callable:
    value = namespace.get(name)
    if not callable(value):
        raise SelectedXcodeBuildOrchestratorError(f"{label} exposes no {name} callable")
    return value


def _require_frozen_tool(tools: dict[object, object], name: str, frozen_developer: Path) -> Path:
    value = tools.get(name)
    if not isinstance(value, Path) or not value.is_absolute():
        raise SelectedXcodeBuildOrchestratorError(f"selected-Xcode freeze exposes no absolute {name} path")
    expected_prefix = str(frozen_developer) + os.sep
    if not str(value).startswith(expected_prefix):
        raise SelectedXcodeBuildOrchestratorError(f"selected {name} escaped the frozen Developer tree")
    if "\t" in str(value) or "\n" in str(value):
        raise SelectedXcodeBuildOrchestratorError(f"selected {name} path contains an invalid separator")
    return value


def _replace_selected_xcode(
    command: Sequence[str],
    *,
    frozen_developer: Path,
    selected_xcodebuild: Path,
) -> list[str]:
    if not command:
        raise SelectedXcodeBuildOrchestratorError("guarded build command is empty")
    if not frozen_developer.is_absolute() or not selected_xcodebuild.is_absolute():
        raise SelectedXcodeBuildOrchestratorError("selected-Xcode authority paths must be absolute")
    expected_prefix = str(frozen_developer) + os.sep
    if not str(selected_xcodebuild).startswith(expected_prefix):
        raise SelectedXcodeBuildOrchestratorError("selected xcodebuild escaped the frozen Developer tree")
    if any(argument.startswith("DEVELOPER_DIR=") for argument in command):
        raise SelectedXcodeBuildOrchestratorError("caller supplied DEVELOPER_DIR authority is forbidden")
    matches = [index for index, argument in enumerate(command) if argument == "/usr/bin/xcodebuild"]
    if len(matches) != 1:
        raise SelectedXcodeBuildOrchestratorError(
            "guarded build must contain exactly one canonical xcodebuild replacement marker"
        )
    index = matches[0]
    return [
        *command[:index],
        "/usr/bin/env",
        f"DEVELOPER_DIR={frozen_developer}",
        str(selected_xcodebuild),
        *command[index + 1 :],
    ]


def orchestrate(
    *,
    field_pid: int,
    source_sha: str,
    freeze_launcher_base64: str,
    freeze_launcher_blob: str,
    freeze_helper_base64: str,
    freeze_helper_blob: str,
    build_origin_base64: str,
    build_origin_blob: str,
    install_custody_base64: str,
    install_custody_blob: str,
    command: Sequence[str],
) -> tuple[Path, str]:
    if sys.platform != "darwin" or os.geteuid() != 0:
        raise SelectedXcodeBuildOrchestratorError("selected-Xcode build composition requires root on macOS")
    if field_pid <= 1:
        raise SelectedXcodeBuildOrchestratorError("field shell PID is invalid")
    if re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
        raise SelectedXcodeBuildOrchestratorError("accepted source SHA is malformed")

    launcher_raw = _decode_verified_git_blob(
        freeze_launcher_base64, freeze_launcher_blob, "selected-Xcode freeze launcher"
    )
    _decode_verified_git_blob(freeze_helper_base64, freeze_helper_blob, "selected-Xcode freeze helper")
    build_origin_raw = _decode_verified_git_blob(
        build_origin_base64, build_origin_blob, "signed build-origin helper"
    )
    _decode_verified_git_blob(install_custody_base64, install_custody_blob, "signed install-custody helper")

    launcher = _load_namespace(
        launcher_raw,
        name="nembra_selected_xcode_freeze_launcher",
        filename="<accepted-selected-xcode-freeze-launcher>",
    )
    launcher_run = _require_callable(launcher, "run", "selected-Xcode freeze launcher")
    freeze_result = launcher_run(field_pid, source_sha, freeze_helper_base64, freeze_helper_blob)
    if not isinstance(freeze_result, tuple) or len(freeze_result) != 4:
        raise SelectedXcodeBuildOrchestratorError("selected-Xcode freeze launcher returned malformed authority")
    _namespace, frozen_developer, tools, _janitor_pid = freeze_result
    if not isinstance(frozen_developer, Path) or not frozen_developer.is_absolute() or not isinstance(tools, dict):
        raise SelectedXcodeBuildOrchestratorError("selected-Xcode freeze launcher returned invalid paths")
    if "\t" in str(frozen_developer) or "\n" in str(frozen_developer):
        raise SelectedXcodeBuildOrchestratorError("frozen Developer path contains an invalid separator")
    selected_xcodebuild = _require_frozen_tool(tools, "xcodebuild", frozen_developer)
    _require_frozen_tool(tools, "xctrace", frozen_developer)
    _require_frozen_tool(tools, "devicectl", frozen_developer)

    guarded_command = _replace_selected_xcode(
        command,
        frozen_developer=frozen_developer,
        selected_xcodebuild=selected_xcodebuild,
    )

    build_origin = _load_namespace(
        build_origin_raw,
        name="nembra_signed_app_build_origin_custody",
        filename="<accepted-build-origin-custody>",
    )
    run_custodied_build = _require_callable(
        build_origin, "run_custodied_build", "signed build-origin helper"
    )
    result = run_custodied_build(
        guarded_command,
        app_relative=Path("Build/Products/Debug-iphoneos/Nembra Capture.app"),
        fingerprint_helper_base64=install_custody_base64,
    )
    if not isinstance(result, tuple) or len(result) != 2:
        raise SelectedXcodeBuildOrchestratorError("signed build-origin helper returned malformed custody result")
    stage_root, fingerprint = result
    if not isinstance(stage_root, Path) or not isinstance(fingerprint, str):
        raise SelectedXcodeBuildOrchestratorError("signed build-origin helper returned invalid custody types")
    return stage_root, fingerprint


def _parse(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Freeze selected Xcode and run one signed Capture build inside exact compiler-output custody"
    )
    parser.add_argument("--field-pid", required=True, type=int)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--freeze-launcher-base64", required=True)
    parser.add_argument("--freeze-launcher-blob", required=True)
    parser.add_argument("--freeze-helper-base64", required=True)
    parser.add_argument("--freeze-helper-blob", required=True)
    parser.add_argument("--build-origin-base64", required=True)
    parser.add_argument("--build-origin-blob", required=True)
    parser.add_argument("--install-custody-base64", required=True)
    parser.add_argument("--install-custody-blob", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(list(argv))
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    return args


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = _parse(sys.argv[1:] if argv is None else argv)
        stage_root, fingerprint = orchestrate(
            field_pid=args.field_pid,
            source_sha=args.source_sha.lower(),
            freeze_launcher_base64=args.freeze_launcher_base64,
            freeze_launcher_blob=args.freeze_launcher_blob,
            freeze_helper_base64=args.freeze_helper_base64,
            freeze_helper_blob=args.freeze_helper_blob,
            build_origin_base64=args.build_origin_base64,
            build_origin_blob=args.build_origin_blob,
            install_custody_base64=args.install_custody_base64,
            install_custody_blob=args.install_custody_blob,
            command=args.command,
        )
        values = (str(stage_root), fingerprint)
        if any("\t" in value or "\n" in value for value in values):
            raise SelectedXcodeBuildOrchestratorError("selected-Xcode build result contains malformed separators")
        sys.stdout.write("\t".join(values) + "\n")
        return 0
    except Exception as error:
        print(f"ERROR: selected-Xcode signed-build composition failed: {error}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())
