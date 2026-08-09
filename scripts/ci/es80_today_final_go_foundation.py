#!/usr/bin/env python3
"""Library-only authority foundation for V14 TODAY Final GO.

The closed-world validator implementation is consumed through this wrapper. Importing the
foundation remains supported for controlled composition and adversarial tests, but executing this
filename is deliberately non-authorizing. The only executable Final GO entrypoint is
`es80_today_final_go_hardened.py`.

Independent retained-candidate crosscheck authority is intentionally stronger at this wrapper than
inside the historical implementation: a caller cannot promote plain JSON by calling
`_crosscheck_subject(...)`. Every authority-bearing `build_final_go_record(...)` execution first
runs the exact pinned crosscheck producer and requires byte-identical handoff output, then delegates
the historical semantic/Git checks against that authenticated receipt.
"""
from __future__ import annotations

import importlib.util
import inspect
from pathlib import Path
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

_TRUSTED_CROSSCHECK_PATH = Path(__file__).with_name("es80_today_trusted_crosscheck_subject.py")
_trusted_spec = importlib.util.spec_from_file_location(
    "nembra_today_final_go_trusted_crosscheck", _TRUSTED_CROSSCHECK_PATH
)
if _trusted_spec is None or _trusted_spec.loader is None:
    raise RuntimeError("could not load trusted Final GO crosscheck authority")
_trusted_crosscheck = importlib.util.module_from_spec(_trusted_spec)
_trusted_spec.loader.exec_module(_trusted_crosscheck)

# Private reference to the historical semantic checker. It remains useful only after the wrapper
# has independently executed the pinned producer; exporting it as an authority surface would reopen
# the caller-authored PASS defect proved by validation #1579.
_semantic_crosscheck_subject = _impl._crosscheck_subject

# Keep these exact source pins visible to canonical source-shape QA while implementation remains
# byte-identical to the previously accepted closed-world validator.
PINNED_CROSSCHECK_COMMIT = "d827a296048386bda62024ea3278775d5344c47c"
PINNED_CROSSCHECK_BLOB = "c3b2b620280484c05316fc5c2fa2ca451f1fdc83"
RESEARCH_COMPILE_MODE = "private-today-v1"
RESEARCH_COMPILE_AUTHORITY = "canonical-producer-explicit-mode"
RESEARCH_COMPILE_CONDITION = "NEMBRA_ES80_TODAY_RESEARCH"


def _crosscheck_subject(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Fail closed: plain caller-authored JSON is never independent execution evidence."""
    del args, kwargs
    raise FinalGoError(
        "independent crosscheck authority requires pinned producer execution through "
        "build_final_go_record; caller-authored receipt JSON is non-authorizing"
    )


def _trusted_crosscheck_receipt(
    *,
    candidate_root: Path,
    expected_source_sha: str,
    supplied_receipt_path: Path,
    tooling_repo: Path,
) -> dict[str, Any]:
    """Production trust seam; tests may replace only inside their own process."""
    try:
        return _trusted_crosscheck.verify_trusted_crosscheck_receipt(
            candidate_root=candidate_root,
            expected_source_sha=expected_source_sha,
            supplied_receipt_path=supplied_receipt_path,
            tooling_repo=tooling_repo,
        )
    except _trusted_crosscheck.TrustedCrosscheckError as error:
        raise FinalGoError(str(error)) from error


def build_final_go_record(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Delegate with trusted Xcode/Git seams and mandatory pinned crosscheck execution."""
    try:
        bound = inspect.signature(_impl.build_final_go_record).bind(*args, **kwargs)
    except TypeError as error:
        raise
    values = bound.arguments

    candidate_root = Path(values["candidate_root"])
    expected_source_sha = str(values["expected_source_sha"])
    receipt_path = Path(values["independent_crosscheck_receipt"])
    frozen_source_repo = Path(values["frozen_source_repo"])
    tooling_repo = Path(values["tooling_repo"])

    trusted_execution = _trusted_crosscheck_receipt(
        candidate_root=candidate_root,
        expected_source_sha=expected_source_sha,
        supplied_receipt_path=receipt_path,
        tooling_repo=tooling_repo,
    )

    def authenticated_crosscheck_subject(
        path: Path,
        candidate: dict[str, Any],
        adapter_frozen_source_repo: Path,
        adapter_tooling_repo: Path,
    ) -> dict[str, Any]:
        if Path(path) != receipt_path:
            raise FinalGoError("foundation crosscheck path diverged from authenticated handoff receipt")
        if Path(adapter_frozen_source_repo) != frozen_source_repo:
            raise FinalGoError("foundation frozen-source repository diverged from authenticated crosscheck")
        if Path(adapter_tooling_repo) != tooling_repo:
            raise FinalGoError("foundation tooling repository diverged from authenticated crosscheck")
        if candidate.get("sourceCommitSHA") != expected_source_sha:
            raise FinalGoError("foundation candidate source diverged from authenticated crosscheck")

        subject = dict(
            _semantic_crosscheck_subject(
                path,
                candidate,
                adapter_frozen_source_repo,
                adapter_tooling_repo,
            )
        )
        subject["trustedProducerExecution"] = trusted_execution
        return subject

    original_git = _impl._git
    original_trusted_xcode_subject = _impl._trusted_xcode_subject
    original_crosscheck_subject = _impl._crosscheck_subject
    _impl._git = globals().get("_git", original_git)
    _impl._trusted_xcode_subject = globals().get(
        "_trusted_xcode_subject", original_trusted_xcode_subject
    )
    _impl._crosscheck_subject = authenticated_crosscheck_subject
    try:
        record = _impl.build_final_go_record(*args, **kwargs)
    finally:
        _impl._git = original_git
        _impl._trusted_xcode_subject = original_trusted_xcode_subject
        _impl._crosscheck_subject = original_crosscheck_subject

    crosscheck_subject = record.get("independentRetainedCandidateCrosscheck")
    if not isinstance(crosscheck_subject, dict):
        raise FinalGoError("Final GO record lacks authenticated independent crosscheck subject")
    execution = crosscheck_subject.get("trustedProducerExecution")
    if not isinstance(execution, dict):
        raise FinalGoError("Final GO record lacks trusted crosscheck producer execution")
    if execution.get("authority") != _trusted_crosscheck.TRUSTED_EXECUTION_AUTHORITY:
        raise FinalGoError("Final GO crosscheck producer execution authority is invalid")
    if execution.get("candidateSourceCommitSHA") != record.get("acceptedSourceCommitSHA"):
        raise FinalGoError("Final GO crosscheck execution source diverged from accepted source")
    if execution.get("producerStatus") != "PASS_NOT_FINAL_GO":
        raise FinalGoError("Final GO crosscheck execution did not preserve PASS_NOT_FINAL_GO")
    if execution.get("physicalExperimentAuthorization") != "not-granted":
        raise FinalGoError("Final GO crosscheck execution widened physical authorization")
    return record


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
