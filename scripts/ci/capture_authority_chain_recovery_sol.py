#!/usr/bin/env python3
"""Recover the staged Capture authority-chain materializer without weakening its red-team contract."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MATERIALIZER = ROOT / ".github/workflows/capture-authority-chain-materialize.yml"
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
YAML_BLOCK_PREFIX = "          "


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
    raw_payload = body.split(end, 1)[0]

    # YAML literal-block content is encoded with exactly ten structural spaces
    # before every physical Python line. Strip that prefix line-by-line instead
    # of textwrap.dedent(), whose global-minimum rule is disturbed by physical
    # continuation lines inside the transformer's own multiline strings.
    decoded: list[str] = []
    for number, line in enumerate(raw_payload.splitlines(keepends=True), start=1):
        if not line.strip():
            decoded.append(line[len(YAML_BLOCK_PREFIX):] if line.startswith(YAML_BLOCK_PREFIX) else line)
            continue
        if not line.startswith(YAML_BLOCK_PREFIX):
            raise SystemExit(f"materializer YAML payload line {number} lost its structural prefix")
        decoded.append(line[len(YAML_BLOCK_PREFIX):])
    payload = "".join(decoded)

    function_start = payload.find("def replace_once(")
    bootstrap_label = payload.find("# Bootstrap:", function_start)
    function_end = payload.rfind("# ------------------------------------------------------------------", function_start, bootstrap_label)
    if function_start < 0 or bootstrap_label < 0 or function_end < 0 or function_end <= function_start:
        raise SystemExit("materializer replace_once function boundary is unavailable")
    repaired = '''def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if label == "bootstrap review helper output" and count == 2:
        candidate = "DEPENDENCY LOCK CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY"
        marker = text.find(candidate)
        if marker < 0:
            raise SystemExit("bootstrap review helper output: review-candidate marker missing")
        prefix, suffix = text[:marker], text[marker:]
        if suffix.count(old) != 1:
            raise SystemExit(f"bootstrap review helper output: expected one review-candidate match, found {suffix.count(old)}")
        return prefix + suffix.replace(old, new, 1)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


'''
    return payload[:function_start] + repaired + payload[function_end:]


def harden_exact_git_execution() -> None:
    text = INSTALLER.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "import subprocess\nimport sys\nfrom pathlib import Path\n\nroot = Path(sys.argv[1])\n",
        "import os\nimport subprocess\nimport sys\nfrom pathlib import Path\n\nroot = Path(sys.argv[1])\n",
        "installer accepted-source imports",
    )
    old = '''    source = subprocess.check_output(
        ["/usr/bin/git", "show", f"{source_sha}:{relative_path}"],
        cwd=root,
        stderr=subprocess.DEVNULL,
    )
'''
    new = '''    git_environment = os.environ.copy()
    git_environment["GIT_NO_REPLACE_OBJECTS"] = "1"
    source = subprocess.check_output(
        ["/usr/bin/git", "show", f"{source_sha}:{relative_path}"],
        cwd=root,
        env=git_environment,
        stderr=subprocess.DEVNULL,
    )
'''
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
