#!/usr/bin/env python3
"""Final-GO successor with a detached record handoff before source-custody release.

Exact parent #3042 closes the demonstrated #3024/#3030 whole-tree mutation races
by holding continuous kernel custody over the accepted tracked candidate while
all source-dependent Final-GO work executes. The remaining teardown question is
not solved by pretending a finite watcher poll can keep a caller-owned checkout
unchanged forever. Instead this successor makes the authority transition
explicit: before #3042 releases tracked-tree custody, the complete Final-GO
result is converted into one detached canonical JSON value, every embedded
``sourceCommitSHA`` is rebound to the accepted source, and any live candidate
pathname reference is rejected.

After that seal exists, the mutable checkout is deliberately no longer an
authority-bearing subject. A same-UID mutation that occurs only after the final
source-dependent result has been detached cannot rewrite that in-memory record
or change the immutable Git source identity it carries. Any later component that
needs source bytes must establish its own custody instead of treating this
returned record as permission to reopen the checkout.

This is an authority handoff, not a claim that watcher teardown makes the live
filesystem immutable. No Bluetooth, Tuya, credential, signing, install, launch,
telemetry, scooter command, or physical evidence semantics are introduced.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import types
from pathlib import Path
from typing import Any

DIRECT_PARENT_SOURCE = "cb36f9265f08708c8e47564f62f4857aeae7af0f"
DIRECT_PARENT_MODULE_PATH = "scripts/ci/es80_authenticated_stationary_private_review_final_go.py"
DIRECT_PARENT_MODULE_GIT_BLOB = "baef9de23a680bedf16f9f7b367f45f7710ac0c6"
MAX_PARENT_BLOB_BYTES = 4 * 1024 * 1024
OID = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")


class FinalGoRecordHandoffError(RuntimeError):
    pass


def _closed_parent_environment() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_CONFIG_COUNT": "2",
        "GIT_CONFIG_KEY_0": "core.fsmonitor",
        "GIT_CONFIG_VALUE_0": "false",
        "GIT_CONFIG_KEY_1": "core.hooksPath",
        "GIT_CONFIG_VALUE_1": "/dev/null",
    }


def _git_blob_oid(payload: bytes, accepted_oid: str) -> str:
    framed = b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    if len(accepted_oid) == 40:
        return hashlib.sha1(framed).hexdigest()
    if len(accepted_oid) == 64:
        return hashlib.sha256(framed).hexdigest()
    raise FinalGoRecordHandoffError("Final-GO parent blob identity has unsupported width")


def _bounded_parent_blob(root: Path) -> bytes:
    marker = root / ".git"
    try:
        metadata = marker.lstat()
    except OSError as error:
        raise FinalGoRecordHandoffError("Final-GO parent Git directory is unavailable") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise FinalGoRecordHandoffError("Final-GO parent requires one real checkout Git directory")

    process: subprocess.Popen[bytes] | None = None
    try:
        process = subprocess.Popen(
            [
                "/usr/bin/git",
                f"--git-dir={marker}",
                "cat-file",
                "blob",
                DIRECT_PARENT_MODULE_GIT_BLOB,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=_closed_parent_environment(),
        )
        if process.stdout is None:
            raise FinalGoRecordHandoffError("Final-GO parent capture pipe is unavailable")
        payload = process.stdout.read(MAX_PARENT_BLOB_BYTES + 1)
        if len(payload) > MAX_PARENT_BLOB_BYTES:
            process.kill()
            process.wait()
            raise FinalGoRecordHandoffError("Final-GO parent bytes exceed the accepted bound")
        returncode = process.wait()
        if returncode != 0 or not payload:
            raise FinalGoRecordHandoffError("Final-GO exact parent bytes could not be captured")
        if _git_blob_oid(payload, DIRECT_PARENT_MODULE_GIT_BLOB) != DIRECT_PARENT_MODULE_GIT_BLOB:
            raise FinalGoRecordHandoffError("Final-GO parent Git lookup returned different bytes")
        return payload
    except OSError as error:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        raise FinalGoRecordHandoffError("Final-GO exact parent bytes could not be captured") from error
    finally:
        if process is not None and process.stdout is not None:
            process.stdout.close()


def _load_direct_parent() -> types.ModuleType:
    root = Path(__file__).resolve().parents[2]
    payload = _bounded_parent_blob(root)
    module_name = "nembra_final_go_continuous_tree_parent_3042"
    module = types.ModuleType(module_name)
    module.__file__ = str(Path(__file__).resolve())
    module.__nembra_exact_parent_source__ = DIRECT_PARENT_SOURCE
    module.__nembra_exact_parent_blob__ = DIRECT_PARENT_MODULE_GIT_BLOB
    sys.modules[module_name] = module
    try:
        exec(
            compile(
                payload,
                f"git:{DIRECT_PARENT_SOURCE}:{DIRECT_PARENT_MODULE_PATH}",
                "exec",
                dont_inherit=True,
            ),
            module.__dict__,
        )
    except Exception as error:
        sys.modules.pop(module_name, None)
        raise FinalGoRecordHandoffError("exact #3042 Final-GO parent could not execute") from error

    try:
        direct_parent = module._direct_parent
        entry = direct_parent._tree_entries(root, DIRECT_PARENT_SOURCE).get(DIRECT_PARENT_MODULE_PATH)
    except Exception as error:
        raise FinalGoRecordHandoffError("exact #3042 parent tree provenance could not be proved") from error
    if entry is None or entry[1] != DIRECT_PARENT_MODULE_GIT_BLOB:
        raise FinalGoRecordHandoffError("Final-GO parent path is not the reviewed #3042 Git blob")
    return module


_parent = _load_direct_parent()

# Preserve #3042's public compatibility surface for existing Final-GO tests and
# consumers. The build() function below is intentionally the only overridden
# production behavior.
generated = _parent.generated
PrivateReviewGoError = _parent.PrivateReviewGoError


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise FinalGoRecordHandoffError("Final-GO detached record contains duplicate JSON key")
        result[key] = value
    return result


def _canonical_record_bytes(record: dict[str, Any]) -> bytes:
    try:
        return json.dumps(
            record,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError, UnicodeError) as error:
        raise FinalGoRecordHandoffError("Final-GO result is not a detached JSON authority value") from error


def _record_source_bindings(value: Any) -> list[str]:
    bindings: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                raise FinalGoRecordHandoffError("Final-GO detached record has a non-string key")
            if key == "sourceCommitSHA":
                if not isinstance(child, str):
                    raise FinalGoRecordHandoffError("Final-GO sourceCommitSHA is not text")
                bindings.append(child)
            bindings.extend(_record_source_bindings(child))
    elif isinstance(value, list):
        for child in value:
            bindings.extend(_record_source_bindings(child))
    return bindings


def _reject_live_candidate_references(value: Any, root: Path) -> None:
    root_text = os.fspath(root)
    root_prefix = root_text.rstrip(os.sep) + os.sep
    if isinstance(value, dict):
        for child in value.values():
            _reject_live_candidate_references(child, root)
        return
    if isinstance(value, list):
        for child in value:
            _reject_live_candidate_references(child, root)
        return
    if isinstance(value, str) and (value == root_text or value.startswith(root_prefix)):
        raise FinalGoRecordHandoffError(
            "Final-GO detached record attempted to retain a live candidate pathname"
        )


def _detach_authority_record(record: Any, root: Path, source: str) -> dict[str, Any]:
    """Create the one-way JSON authority handoff while #3042 custody is armed."""
    if not isinstance(record, dict):
        raise FinalGoRecordHandoffError("Final-GO parent did not return one authority object")
    source = source.lower()
    if not OID.fullmatch(source):
        raise FinalGoRecordHandoffError("Final-GO accepted source is not canonical")

    raw = _canonical_record_bytes(record)
    try:
        detached = json.loads(raw.decode("utf-8"), object_pairs_hook=_reject_duplicate_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise FinalGoRecordHandoffError("Final-GO canonical record could not be detached") from error
    if not isinstance(detached, dict):
        raise FinalGoRecordHandoffError("Final-GO detached record root is not one object")

    bindings = _record_source_bindings(detached)
    if not bindings:
        raise FinalGoRecordHandoffError("Final-GO detached record carries no sourceCommitSHA binding")
    for binding in bindings:
        if binding.lower() != source or binding != binding.lower() or not OID.fullmatch(binding):
            raise FinalGoRecordHandoffError(
                "Final-GO detached record carries source authority outside the accepted source"
            )

    _reject_live_candidate_references(detached, root)

    # Re-encode after validation so the returned object is known to be a pure
    # detached JSON value and not an alias to parent-owned mutable containers.
    final_raw = _canonical_record_bytes(detached)
    if final_raw != raw:
        raise FinalGoRecordHandoffError("Final-GO detached record canonicalization was not stable")
    return detached


def _detached_record_sha256(record: dict[str, Any]) -> str:
    """Diagnostic digest for tests/publication; it is not new physical evidence."""
    return hashlib.sha256(_canonical_record_bytes(record)).hexdigest()


def build(
    *,
    candidate_repo: Path,
    source: str,
    base_module: Any | None = None,
    **kwargs: Any,
) -> dict[str, Any]:
    """Return only a detached Final-GO record; never return live checkout authority."""
    root = candidate_repo.expanduser().resolve(strict=True)
    base = base_module or generated._load_base_module()
    source = base.canon(source, "source")

    # Reproduce exact #3042 build composition, but evaluate and detach the
    # complete parent record before either authority context can release.
    with _parent._candidate_git_custody(base, root, source), _parent._direct_parent._current_vnode_authority():
        record = _parent._direct_parent._parent.build(
            candidate_repo=root,
            source=source,
            base_module=base,
            **kwargs,
        )
        detached = _detach_authority_record(record, root, source)

    # There are deliberately no candidate_repo/source-path reads below this
    # line. Watcher teardown may no longer promise live-path stability; the only
    # returned authority is the already-detached source-bound JSON value.
    return detached


def __getattr__(name: str) -> Any:
    return getattr(_parent, name)


if __name__ == "__main__":
    raise SystemExit(
        "This exact-parent Final-GO sealed-record successor is exercised by exact-head validation; "
        "physical publication remains NO-GO until final composed authority is accepted."
    )
