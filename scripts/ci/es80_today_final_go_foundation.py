#!/usr/bin/env python3
"""Library-only authority foundation for V14 TODAY Final GO.

The closed-world validator implementation is consumed by the canonical hardened composer through
this module. Importing the foundation remains supported for controlled composition and adversarial
tests, but executing this filename is deliberately non-authorizing. The only executable Final GO
entrypoint is `es80_today_final_go_hardened.py`.

The independent retained-candidate receipt is not trusted merely because it names the accepted
crosscheck tool. Before that receipt can become part of a Final-GO subject, this wrapper executes
the exact pinned Git-blob bytes of the independent crosscheck against the exact candidate directory
and requires the supplied receipt bytes to be exactly the canonical output of that execution.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
from typing import Any

_IMPL_PATH = Path(__file__).with_name("_es80_today_final_go_foundation_impl.py")
_spec = importlib.util.spec_from_file_location("nembra_today_final_go_foundation_impl", _IMPL_PATH)
if _spec is None or _spec.loader is None:
    raise RuntimeError("could not load Final GO foundation implementation")
_impl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_impl)

for _name in dir(_impl):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_impl, _name)

# Keep these exact source pins visible to canonical source-shape QA while implementation remains
# byte-identical to the previously accepted closed-world validator.
PINNED_CROSSCHECK_COMMIT = "d827a296048386bda62024ea3278775d5344c47c"
PINNED_CROSSCHECK_BLOB = "c3b2b620280484c05316fc5c2fa2ca451f1fdc83"
RESEARCH_COMPILE_MODE = "private-today-v1"
RESEARCH_COMPILE_AUTHORITY = "canonical-producer-explicit-mode"
RESEARCH_COMPILE_CONDITION = "NEMBRA_ES80_TODAY_RESEARCH"

_ORIGINAL_CROSSCHECK_SUBJECT = _impl._crosscheck_subject


def _closed_git_blob_bytes(repository: Path, object_id: str) -> bytes:
    """Read one exact Git blob through the same closed producer-owned Git boundary."""
    try:
        metadata = repository.lstat()
    except OSError as error:
        raise FinalGoError(f"Git repository is unavailable: {repository}") from error
    if repository.is_symlink() or not stat.S_ISDIR(metadata.st_mode):
        raise FinalGoError(f"Git repository must be one real non-symlink directory: {repository}")
    environment = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": "/tmp",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
    }
    try:
        raw = subprocess.check_output(
            ["/usr/bin/git", "-C", str(repository.resolve()), "cat-file", "blob", object_id],
            env=environment,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise FinalGoError("pinned independent crosscheck Git blob is unreadable") from error
    if not raw:
        raise FinalGoError("pinned independent crosscheck Git blob is empty")
    if len(object_id) == 40:
        computed = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        if computed != object_id:
            raise FinalGoError("pinned independent crosscheck Git blob bytes changed during read")
    return raw


def _trusted_crosscheck_execution(
    *,
    receipt_path: Path,
    candidate_root: Path,
    expected_source_sha: str,
    tooling_repo: Path,
    now_utc: Any,
) -> tuple[dict[str, Any], bytes, str]:
    """Execute the exact pinned independent crosscheck and return its canonical receipt bytes."""
    git_lookup = globals().get("_git", _impl._git)
    commit = git_lookup(
        tooling_repo,
        "rev-parse",
        "--verify",
        f"{PINNED_CROSSCHECK_COMMIT}^{{commit}}",
    )
    if commit != PINNED_CROSSCHECK_COMMIT:
        raise FinalGoError("pinned independent crosscheck tooling commit mismatch")
    tool_blob = git_lookup(
        tooling_repo,
        "rev-parse",
        f"{PINNED_CROSSCHECK_COMMIT}:{CROSSCHECK_PATH}",
    )
    if tool_blob != PINNED_CROSSCHECK_BLOB:
        raise FinalGoError("pinned independent crosscheck tool Git blob mismatch")

    source_bytes = _closed_git_blob_bytes(tooling_repo, tool_blob)
    try:
        source_text = source_bytes.decode("utf-8")
    except UnicodeDecodeError as error:
        raise FinalGoError("pinned independent crosscheck source is not UTF-8") from error

    namespace: dict[str, Any] = {
        "__name__": "nembra_pinned_independent_candidate_crosscheck",
        "__file__": CROSSCHECK_PATH,
        "__package__": None,
    }
    try:
        exec(compile(source_text, CROSSCHECK_PATH, "exec"), namespace)
    except Exception as error:
        raise FinalGoError("pinned independent crosscheck source could not be loaded") from error

    crosscheck = namespace.get("crosscheck")
    crosscheck_error = namespace.get("CrosscheckError")
    if not callable(crosscheck) or not isinstance(crosscheck_error, type):
        raise FinalGoError("pinned independent crosscheck source lacks canonical entrypoint")
    try:
        derived = crosscheck(
            candidate_root.expanduser().absolute(),
            expected_source_sha=expected_source_sha,
            now=now_utc,
        )
    except crosscheck_error as error:
        raise FinalGoError(f"pinned independent retained-candidate crosscheck failed: {error}") from error
    except Exception as error:
        raise FinalGoError("pinned independent retained-candidate crosscheck execution failed") from error
    if not isinstance(derived, dict):
        raise FinalGoError("pinned independent crosscheck did not return one receipt object")

    canonical = (json.dumps(derived, indent=2, sort_keys=True) + "\n").encode("utf-8")
    return derived, canonical, tool_blob


def _crosscheck_subject(
    path: Path,
    candidate: dict[str, Any],
    frozen_source_repo: Path,
    tooling_repo: Path,
    *,
    candidate_root: Path | None = None,
    now_utc: Any = None,
) -> dict[str, Any]:
    """Accept a crosscheck only when the pinned producer reproduces the exact supplied receipt."""
    if candidate_root is None:
        raise FinalGoError(
            "independent crosscheck authority requires the exact retained candidate root for producer execution"
        )

    legacy_subject = _ORIGINAL_CROSSCHECK_SUBJECT(
        path,
        candidate,
        frozen_source_repo,
        tooling_repo,
    )
    raw, supplied = _impl._json_file(
        path,
        "independent retained-candidate cross-check receipt",
        exact_keys=CROSSCHECK_KEYS,
    )
    executor = globals().get("_trusted_crosscheck_execution", _trusted_crosscheck_execution)
    derived, canonical, tool_blob = executor(
        receipt_path=path,
        candidate_root=candidate_root,
        expected_source_sha=candidate["sourceCommitSHA"],
        tooling_repo=tooling_repo,
        now_utc=now_utc,
    )
    if supplied != derived:
        raise FinalGoError(
            "independent retained-candidate receipt was not reproduced by the pinned crosscheck producer"
        )
    if raw != canonical:
        raise FinalGoError(
            "independent retained-candidate receipt bytes are not the exact canonical pinned-producer output"
        )
    receipt_sha = hashlib.sha256(raw).hexdigest()
    if legacy_subject.get("receiptSHA256") != receipt_sha:
        raise FinalGoError("independent crosscheck receipt digest diverged during trusted reproduction")

    result = dict(legacy_subject)
    result.update(
        {
            "producerExecutionAuthority": "pinned-crosscheck-git-blob-execution-v1",
            "executedToolCommit": PINNED_CROSSCHECK_COMMIT,
            "executedToolGitBlob": tool_blob,
            "executedReceiptSHA256": receipt_sha,
        }
    )
    return result


def build_final_go_record(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Delegate as a library while composing trusted Xcode/Git/crosscheck execution seams."""
    if args:
        raise FinalGoError("Final GO foundation builder accepts keyword arguments only")
    candidate_root = kwargs.get("candidate_root")
    if not isinstance(candidate_root, Path):
        raise FinalGoError("Final GO foundation requires one exact candidate_root Path")
    now_utc = kwargs.get("now_utc")

    original_git = _impl._git
    original_trusted_xcode_subject = _impl._trusted_xcode_subject
    original_crosscheck_subject = _impl._crosscheck_subject
    _impl._git = globals().get("_git", original_git)
    _impl._trusted_xcode_subject = globals().get(
        "_trusted_xcode_subject", original_trusted_xcode_subject
    )
    _impl._crosscheck_subject = lambda path, candidate, frozen_source_repo, tooling_repo: _crosscheck_subject(
        path,
        candidate,
        frozen_source_repo,
        tooling_repo,
        candidate_root=candidate_root,
        now_utc=now_utc,
    )
    try:
        return _impl.build_final_go_record(**kwargs)
    finally:
        _impl._git = original_git
        _impl._trusted_xcode_subject = original_trusted_xcode_subject
        _impl._crosscheck_subject = original_crosscheck_subject


def publish_record_no_replace(*args: Any, **kwargs: Any) -> str:
    return _impl.publish_record_no_replace(*args, **kwargs)


def main(argv: list[str] | None = None) -> int:
    del argv
    print(
        "TODAY Final GO: NO-GO: Final GO foundation is library-only and non-authorizing when "
        "executed directly; use es80_today_final_go_hardened.py",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
