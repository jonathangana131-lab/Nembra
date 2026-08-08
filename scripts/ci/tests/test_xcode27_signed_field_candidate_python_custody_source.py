#!/usr/bin/env python3
"""Source regression for Python interpreter custody in signed-field candidate production."""

from __future__ import annotations

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[3]
PRODUCER = ROOT / "scripts/ci/xcode27_signed_field_candidate.sh"


def main() -> None:
    source = PRODUCER.read_text(encoding="utf-8")

    if 'PYTHON3="/usr/bin/python3"' not in source:
        raise AssertionError("signed-field producer does not pin system Python")
    if '[[ ! -x "$PYTHON3" ]]' not in source:
        raise AssertionError("signed-field producer does not fail closed when pinned Python is unavailable")
    if re.search(r'(?m)^\s*python3(?:\s|$)', source):
        raise AssertionError("signed-field producer still executes Python through ambient PATH")
    if "$(python3 " in source:
        raise AssertionError("signed-field producer still command-substitutes ambient Python")

    invocations = re.findall(r'(?m)^\s*"\$PYTHON3"[^\n]*', source)
    if not invocations:
        raise AssertionError("signed-field producer has no pinned Python invocations")
    non_isolated = [line for line in invocations if not re.search(r'"\$PYTHON3"\s+-I(?:\s|$)', line)]
    if non_isolated:
        raise AssertionError(
            "every evidence-producing pinned Python invocation must use isolated mode: "
            + " | ".join(non_isolated)
        )

    required = [
        '"$PYTHON3" -I /dev/fd/7',
        '"$PYTHON3" -I /dev/fd/9',
        '"$PYTHON3" -I --version',
    ]
    for needle in required:
        if needle not in source:
            raise AssertionError(f"missing Python custody contract: {needle}")

    if source.index("REPOSITORY_STATUS=") >= source.index('"$PYTHON3" -I /dev/fd/7'):
        raise AssertionError("private preflight runner executes before clean-repository admission")
    if source.index('"$PYTHON3" -I /dev/fd/7') >= source.index("git worktree add --detach"):
        raise AssertionError("private input preflight no longer runs before expensive field build work")

    print("signed-field candidate Python custody source regression: PASS")


if __name__ == "__main__":
    main()
