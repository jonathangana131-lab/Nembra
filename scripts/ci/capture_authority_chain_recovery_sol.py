#!/usr/bin/env python3
"""Recover the staged Capture authority-chain materializer without weakening its red-team contract."""
from __future__ import annotations

from pathlib import Path
import textwrap

ROOT = Path(__file__).resolve().parents[2]
MATERIALIZER = ROOT / ".github/workflows/capture-authority-chain-materialize.yml"
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def materializer_payload() -> str:
    workflow = MATERIALIZER.read_text(encoding="utf-8")
    start = "          python3 - <<'PY'\n"
    end = "\n          PY\n"
    if workflow.count(start) != 1:
        raise SystemExit("materializer payload start is not unique")
    body = workflow.split(start, 1)[1]
    if body.count(end) != 1:
        raise SystemExit("materializer payload end is not unique")
    payload = textwrap.dedent(body.split(end, 1)[0])

    original = '''def replace_once(text: str, old: str, new: str, label: str) -> str:\n    count = text.count(old)\n    if count != 1:\n        raise SystemExit(f"{label}: expected one match, found {count}")\n    return text.replace(old, new, 1)\n'''
    repaired = '''def replace_once(text: str, old: str, new: str, label: str) -> str:\n    count = text.count(old)\n    if label == "bootstrap review helper output" and count == 2:\n        candidate = "DEPENDENCY LOCK CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY"\n        marker = text.find(candidate)\n        if marker < 0:\n            raise SystemExit("bootstrap review helper output: review-candidate marker missing")\n        prefix, suffix = text[:marker], text[marker:]\n        if suffix.count(old) != 1:\n            raise SystemExit(f"bootstrap review helper output: expected one review-candidate match, found {suffix.count(old)}")\n        return prefix + suffix.replace(old, new, 1)\n    if count != 1:\n        raise SystemExit(f"{label}: expected one match, found {count}")\n    return text.replace(old, new, 1)\n'''
    return replace_once(payload, original, repaired, "payload replace_once recovery")


def harden_exact_git_execution() -> None:
    text = INSTALLER.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "import subprocess\nimport sys\nfrom pathlib import Path\n\nroot = Path(sys.argv[1])\n",
        "import os\nimport subprocess\nimport sys\nfrom pathlib import Path\n\nroot = Path(sys.argv[1])\n",
        "installer accepted-source imports",
    )
    old = '''    source = subprocess.check_output(\n        ["/usr/bin/git", "show", f"{source_sha}:{relative_path}"],\n        cwd=root,\n        stderr=subprocess.DEVNULL,\n    )\n'''
    new = '''    git_environment = os.environ.copy()\n    git_environment["GIT_NO_REPLACE_OBJECTS"] = "1"\n    source = subprocess.check_output(\n        ["/usr/bin/git", "show", f"{source_sha}:{relative_path}"],\n        cwd=root,\n        env=git_environment,\n        stderr=subprocess.DEVNULL,\n    )\n'''
    text = replace_once(text, old, new, "replacement-blind accepted Git source")
    if 'git_environment["GIT_NO_REPLACE_OBJECTS"] = "1"' not in text:
        raise SystemExit("replacement-blind Git fence missing after recovery")
    INSTALLER.write_text(text, encoding="utf-8")


def main() -> int:
    namespace: dict[str, object] = {}
    exec(compile(materializer_payload(), "<capture-authority-chain-recovery>", "exec"), namespace)
    harden_exact_git_execution()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
