#!/usr/bin/env python3
"""Recover the staged Capture authority-chain materializer without weakening its red-team contract."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MATERIALIZER = ROOT / ".github/workflows/capture-authority-chain-materialize.yml"
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
GUARD = ROOT / "Scripts/capture_tuya_private_input_build_guard.py"
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

    # Decode the YAML literal block one physical line at a time. Normal Python
    # lines carry the ten-space YAML structural prefix. A few physical
    # continuation lines embedded in the transformer's string literals do not;
    # those bytes are intentional payload content and must be preserved rather
    # than rejected or made to influence a global dedent calculation.
    decoded: list[str] = []
    for line in raw_payload.splitlines(keepends=True):
        if line.startswith(YAML_BLOCK_PREFIX):
            decoded.append(line[len(YAML_BLOCK_PREFIX):])
        else:
            decoded.append(line)
    payload = "".join(decoded)

    function_start = payload.find("def replace_once(")
    bootstrap_label = payload.find("# Bootstrap:", function_start)
    function_end = payload.rfind("# ------------------------------------------------------------------", function_start, bootstrap_label)
    if function_start < 0 or bootstrap_label < 0 or function_end < 0 or function_end <= function_start:
        raise SystemExit("materializer replace_once function boundary is unavailable")
    repaired = '''def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if label == "bootstrap review helper output" and count == 2:
        # The first occurrence is inside the review-only candidate summary.
        # A later dedicated transform intentionally owns the second occurrence
        # in the normal verified-authority summary.
        return text.replace(old, new, 1)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


'''
    return payload[:function_start] + repaired + payload[function_end:]


def canonicalize_generated_guard_authority_block() -> None:
    """Replace the materializer's whitespace-damaged generated loader atomically."""
    text = GUARD.read_text(encoding="utf-8")
    start_marker = 'PRIVATE_REVIEW_HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256"\n'
    end_marker = "\n\n@dataclass(frozen=True)\nclass PrivateInputs:"
    start = text.find(start_marker)
    end = text.find(end_marker, start)
    if start < 0 or end < 0:
        raise SystemExit("generated guard authority block boundary is unavailable")

    block = '''PRIVATE_REVIEW_HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256"
PROVENANCE_HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_PROVENANCE_HELPER_SHA256"
GENERATED_BUILD_SUBJECT_HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_SUBJECT_HELPER_SHA256"
AUTHORITY_HELPER_MAX_BYTES = 262_144


def _load_accepted_helper_module(filename: str, module_name: str, environment_name: str):
    expected = os.environ.get(environment_name, "").lower()
    if len(expected) != 64 or any(character not in "0123456789abcdef" for character in expected):
        raise BuildGuardError(
            f"{environment_name} must remain available as exactly 64 hex characters through build-window admission"
        )
    helper = Path(__file__).with_name(filename)
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(helper, flags)
    except OSError as error:
        raise BuildGuardError(
            f"accepted authority helper could not be opened under descriptor custody: {filename}"
        ) from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise BuildGuardError(
                f"accepted authority helper is not one regular single-link file: {filename}"
            )
        if before.st_size <= 0 or before.st_size > AUTHORITY_HELPER_MAX_BYTES:
            raise BuildGuardError(
                f"accepted authority helper size is outside the accepted bound: {filename}"
            )
        chunks: list[bytes] = []
        remaining = before.st_size
        while remaining:
            chunk = os.read(descriptor, min(65_536, remaining))
            if not chunk:
                raise BuildGuardError(
                    f"accepted authority helper changed during descriptor read: {filename}"
                )
            chunks.append(chunk)
            remaining -= len(chunk)
        source = b"".join(chunks)
        after = os.fstat(descriptor)
        if _stat_identity(before) != _stat_identity(after):
            raise BuildGuardError(
                f"accepted authority helper changed during descriptor custody: {filename}"
            )
    finally:
        os.close(descriptor)
    actual = hashlib.sha256(source).hexdigest()
    if not hmac.compare_digest(actual, expected):
        raise BuildGuardError(
            f"accepted authority helper source does not match externally reviewed authority: {filename}"
        )
    module = types.ModuleType(module_name)
    module.__file__ = f"<accepted-{filename}>"
    try:
        exec(compile(source, module.__file__, "exec"), module.__dict__)
    except Exception as error:
        raise BuildGuardError(
            f"accepted authority helper source could not be loaded: {filename}"
        ) from error
    return module


class _AuthorityHelperProxy:
    def __init__(self, filename: str, module_name: str, environment_name: str) -> None:
        self._filename = filename
        self._module_name = module_name
        self._environment_name = environment_name
        self._module = None

    def require_accepted(self):
        self._module = _load_accepted_helper_module(
            self._filename,
            self._module_name,
            self._environment_name,
        )
        return self._module

    def __getattr__(self, name: str):
        if self._module is None:
            # Compatibility for isolated non-field callers only. The production
            # CLI invokes require_accepted() for both helpers before use.
            self._module = _load_neighbor_module(self._filename, self._module_name)
        return getattr(self._module, name)


provenance = _AuthorityHelperProxy(
    "capture_tuya_private_input_provenance.py",
    "capture_tuya_private_input_provenance",
    PROVENANCE_HELPER_ENV,
)
generated_build = _AuthorityHelperProxy(
    "capture_cocoapods_generated_build_subject.py",
    "capture_cocoapods_generated_build_subject",
    GENERATED_BUILD_SUBJECT_HELPER_ENV,
)


def _load_accepted_private_review_module():
    return _load_accepted_helper_module(
        "capture_private_review_commitment.py",
        "capture_private_review_commitment_accepted",
        PRIVATE_REVIEW_HELPER_ENV,
    )
'''
    GUARD.write_text(text[:start] + block + text[end:], encoding="utf-8")


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
    canonicalize_generated_guard_authority_block()
    harden_exact_git_execution()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
