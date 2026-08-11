#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re


def replace_once(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exact subject once, found {count}: {old[:80]!r}")
    path.write_text(source.replace(old, new), encoding="utf-8")


def regex_once(path: Path, pattern: str, replacement: str, *, flags: int = 0) -> None:
    source = path.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, source, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"{path}: expected regex subject once, found {count}: {pattern[:100]!r}")
    path.write_text(updated, encoding="utf-8")


# ---------------------------------------------------------------------------
# Bootstrap: review publishes helper source identity; field mode executes only
# the captured bytes that match that externally accepted identity.
# ---------------------------------------------------------------------------
bootstrap = Path("Scripts/bootstrap_capture_tuya_sdk.sh")
replace_once(
    bootstrap,
    '  : "${NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 to the preaccepted 64-hex opaque private review commitment before field bootstrap.}"\n',
    '  : "${NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 to the preaccepted 64-hex opaque private review commitment before field bootstrap.}"\n'
    '  : "${NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256 to the preaccepted 64-hex private-review verifier source SHA-256 before field bootstrap.}"\n',
)
replace_once(
    bootstrap,
    '  [[ "$NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {\n'
    '    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 must be exactly 64 hex characters." >&2\n'
    '    exit 1\n'
    '  }\n',
    '  [[ "$NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {\n'
    '    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 must be exactly 64 hex characters." >&2\n'
    '    exit 1\n'
    '  }\n'
    '  [[ "$NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {\n'
    '    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256 must be exactly 64 hex characters." >&2\n'
    '    exit 1\n'
    '  }\n',
)
replace_once(
    bootstrap,
    '  ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256="$(printf \'%s\' "$NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256" | tr \'[:upper:]\' \'[:lower:]\')"\n',
    '  ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256="$(printf \'%s\' "$NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256" | tr \'[:upper:]\' \'[:lower:]\')"\n'
    '  ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256="$(printf \'%s\' "$NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256" | tr \'[:upper:]\' \'[:lower:]\')"\n',
)
replace_once(
    bootstrap,
    '  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 \\\n'
    '    NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 \\\n'
    '    NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 || true\n'
    '  ACCEPTED_LOCK_SHA256=""\n'
    '  ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256=""\n'
    '  ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256=""\n',
    '  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 \\\n'
    '    NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 \\\n'
    '    NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 \\\n'
    '    NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256 || true\n'
    '  ACCEPTED_LOCK_SHA256=""\n'
    '  ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256=""\n'
    '  ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256=""\n'
    '  ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256=""\n',
)
required_loop = '''for required_source in "$PROVENANCE_HELPER" "$PRIVATE_REVIEW_HELPER" "$GENERATED_BUILD_SUBJECT_HELPER"; do
  [[ -f "$required_source" ]] || {
    echo "ERROR: required accepted Capture authority helper is missing: $required_source" >&2
    exit 6
  }
done
unset required_source
'''
accepted_loader = required_loop + r'''

run_accepted_private_review_helper() {
  local expected_sha256="$1"
  shift
  /usr/bin/python3 -I - "$PRIVATE_REVIEW_HELPER" "$expected_sha256" "$@" <<'PY'
import hashlib
import hmac
import os
import stat
import sys

path = sys.argv[1]
expected = sys.argv[2].lower()
helper_argv = sys.argv[3:]
if len(expected) != 64 or any(character not in "0123456789abcdef" for character in expected):
    print("ERROR: accepted private-review verifier source digest is malformed", file=sys.stderr)
    raise SystemExit(72)
flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
try:
    descriptor = os.open(path, flags)
except OSError as error:
    print(f"ERROR: accepted private-review verifier source could not be opened: {error}", file=sys.stderr)
    raise SystemExit(73)
try:
    before = os.fstat(descriptor)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size <= 0 or before.st_size > 262144:
        print("ERROR: private-review verifier source is not one bounded regular single-link file", file=sys.stderr)
        raise SystemExit(74)
    chunks = []
    remaining = before.st_size
    while remaining:
        chunk = os.read(descriptor, min(65536, remaining))
        if not chunk:
            print("ERROR: private-review verifier source changed during descriptor read", file=sys.stderr)
            raise SystemExit(75)
        chunks.append(chunk)
        remaining -= len(chunk)
    source = b"".join(chunks)
    after = os.fstat(descriptor)
    before_identity = (before.st_dev, before.st_ino, before.st_mode, before.st_size, before.st_mtime_ns, before.st_ctime_ns, before.st_nlink)
    after_identity = (after.st_dev, after.st_ino, after.st_mode, after.st_size, after.st_mtime_ns, after.st_ctime_ns, after.st_nlink)
    if before_identity != after_identity:
        print("ERROR: private-review verifier source changed during descriptor custody", file=sys.stderr)
        raise SystemExit(76)
finally:
    os.close(descriptor)
actual = hashlib.sha256(source).hexdigest()
if not hmac.compare_digest(actual, expected):
    print("ERROR: private-review verifier source does not match the externally reviewed digest", file=sys.stderr)
    raise SystemExit(77)
namespace = {"__name__": "__main__", "__file__": "<accepted-private-review-verifier>"}
sys.argv = [path, *helper_argv]
exec(compile(source, "<accepted-private-review-verifier>", "exec"), namespace)
PY
}
'''
replace_once(bootstrap, required_loop, accepted_loader)

regex_once(
    bootstrap,
    r'''  PRIVATE_REVIEW_COMMITMENT_SHA256="\$\(/usr/bin/python3 -I "\$PRIVATE_REVIEW_HELPER" create \\\n    --witness "\$DEPENDENCY_PROVENANCE" \\\n    --key "\$PRIVATE_REVIEW_KEY"\)" \|\| \{
      echo "ERROR: opaque private-input review commitment could not be created\." >&2
      exit 18
    \}
''',
    '''  PRIVATE_REVIEW_COMMITMENT_SHA256="$(/usr/bin/python3 -I "$PRIVATE_REVIEW_HELPER" create \\
    --witness "$DEPENDENCY_PROVENANCE" \\
    --key "$PRIVATE_REVIEW_KEY")" || {
      echo "ERROR: opaque private-input review commitment could not be created." >&2
      exit 18
    }
  PRIVATE_REVIEW_HELPER_SHA256="$(shasum -a 256 "$PRIVATE_REVIEW_HELPER" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
''',
)
regex_once(
    bootstrap,
    r'''  /usr/bin/python3 -I "\$PRIVATE_REVIEW_HELPER" verify \\\n    --witness "\$DEPENDENCY_PROVENANCE" \\\n    --key "\$PRIVATE_REVIEW_KEY" \\\n    --expected "\$ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256" >/dev/null \|\| \{
      echo "ERROR: local private-input witness/key do not match the externally accepted private review commitment\." >&2
      exit 18
    \}
''',
    '''  run_accepted_private_review_helper "$ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256" verify \\
    --witness "$DEPENDENCY_PROVENANCE" \\
    --key "$PRIVATE_REVIEW_KEY" \\
    --expected "$ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256" >/dev/null || {
      echo "ERROR: local private-input witness/key or verifier source do not match the externally accepted private review authority." >&2
      exit 18
    }
  PRIVATE_REVIEW_HELPER_SHA256="$ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256"
''',
)
replace_once(
    bootstrap,
    '  Private review commitment SHA-256: $PRIVATE_REVIEW_COMMITMENT_SHA256\n',
    '  Private review commitment SHA-256: $PRIVATE_REVIEW_COMMITMENT_SHA256\n'
    '  Private review verifier source SHA-256: $PRIVATE_REVIEW_HELPER_SHA256\n',
)
replace_once(
    bootstrap,
    'Review and bind all THREE public authority values to the exact accepted Capture\n',
    'Review and bind all FOUR public authority values to the exact accepted Capture\n',
)
replace_once(
    bootstrap,
    "printf 'Externally accepted opaque private review commitment matched: %s\\n' \"$PRIVATE_REVIEW_COMMITMENT_SHA256\"\n",
    "printf 'Externally accepted opaque private review commitment matched: %s\\n' \"$PRIVATE_REVIEW_COMMITMENT_SHA256\"\n"
    "printf 'Externally accepted private review verifier source matched: %s\\n' \"$PRIVATE_REVIEW_HELPER_SHA256\"\n",
)
replace_once(
    bootstrap,
    'unset ACCEPTED_LOCK_SHA256 ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256 ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 \\\n'
    '  NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 \\\n'
    '  NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 \\\n'
    '  NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 || true\n',
    'unset ACCEPTED_LOCK_SHA256 ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256 ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256 \\\n'
    '  NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 \\\n'
    '  NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 \\\n'
    '  NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 \\\n'
    '  NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256 || true\n',
)
replace_once(
    bootstrap,
    '  Opaque private review commitment SHA-256: $PRIVATE_REVIEW_COMMITMENT_SHA256\n',
    '  Opaque private review commitment SHA-256: $PRIVATE_REVIEW_COMMITMENT_SHA256\n'
    '  Private review verifier source SHA-256: $PRIVATE_REVIEW_HELPER_SHA256\n',
)


# ---------------------------------------------------------------------------
# Build guard: do not import private-review verifier from mutable neighboring
# path. Descriptor-read + hash the current source, then compile only the exact
# accepted bytes into an in-memory module.
# ---------------------------------------------------------------------------
guard = Path("Scripts/capture_tuya_private_input_build_guard.py")
replace_once(guard, "import argparse\n", "import argparse\nimport hashlib\n")
replace_once(guard, "import sys\n", "import sys\nimport types\n")
replace_once(
    guard,
    '''private_review = _load_neighbor_module(
    "capture_private_review_commitment.py",
    "capture_private_review_commitment",
)


@dataclass(frozen=True)
''',
    '''PRIVATE_REVIEW_HELPER_ENV = "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256"
PRIVATE_REVIEW_HELPER_MAX_BYTES = 262_144


def _load_accepted_private_review_module():
    expected = os.environ.get(PRIVATE_REVIEW_HELPER_ENV, "").lower()
    if len(expected) != 64 or any(character not in "0123456789abcdef" for character in expected):
        raise BuildGuardError(
            f"{PRIVATE_REVIEW_HELPER_ENV} must remain available as exactly 64 hex characters through build-window admission"
        )
    helper = Path(__file__).with_name("capture_private_review_commitment.py")
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(helper, flags)
    except OSError as error:
        raise BuildGuardError("private-review verifier source could not be opened under descriptor custody") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise BuildGuardError("private-review verifier source is not one regular single-link file")
        if before.st_size <= 0 or before.st_size > PRIVATE_REVIEW_HELPER_MAX_BYTES:
            raise BuildGuardError("private-review verifier source size is outside the accepted bound")
        chunks: list[bytes] = []
        remaining = before.st_size
        while remaining:
            chunk = os.read(descriptor, min(65_536, remaining))
            if not chunk:
                raise BuildGuardError("private-review verifier source changed during descriptor read")
            chunks.append(chunk)
            remaining -= len(chunk)
        source = b"".join(chunks)
        after = os.fstat(descriptor)
        if provenance._stat_identity(before) != provenance._stat_identity(after):
            raise BuildGuardError("private-review verifier source changed during descriptor custody")
    finally:
        os.close(descriptor)
    actual = hashlib.sha256(source).hexdigest()
    if not hmac.compare_digest(actual, expected):
        raise BuildGuardError("private-review verifier source does not match externally accepted authority")
    module = types.ModuleType("capture_private_review_commitment_accepted")
    module.__file__ = "<accepted-private-review-verifier>"
    try:
        exec(compile(source, module.__file__, "exec"), module.__dict__)
    except Exception as error:
        raise BuildGuardError("accepted private-review verifier source could not be loaded") from error
    return module


@dataclass(frozen=True)
''',
)
replace_once(
    guard,
    '''def _verify_accepted_private_review_commitment(inputs: PrivateInputs) -> None:
    accepted = _accepted_private_review_commitment_from_environment()
    try:
        private_review.verify_commitment(
            witness=inputs.private_provenance_record,
            key_path=inputs.private_review_key,
            expected_tag=accepted,
        )
''',
    '''def _verify_accepted_private_review_commitment(inputs: PrivateInputs) -> None:
    accepted = _accepted_private_review_commitment_from_environment()
    private_review = _load_accepted_private_review_module()
    try:
        private_review.verify_commitment(
            witness=inputs.private_provenance_record,
            key_path=inputs.private_review_key,
            expected_tag=accepted,
        )
''',
)


# ---------------------------------------------------------------------------
# Acceptance fixtures: carry the new public helper source digest in every
# normal-field/build-guard path while leaving review-only creation unchanged.
# ---------------------------------------------------------------------------
private_test = Path("scripts/ci/tests/test_capture_private_review_commitment.py")
replace_once(
    private_test,
    '        for source in (BOOTSTRAP, PROVENANCE, COMMITMENT, GENERATED):\n            shutil.copy2(source, scripts / source.name)\n\n',
    '        for source in (BOOTSTRAP, PROVENANCE, COMMITMENT, GENERATED):\n            shutil.copy2(source, scripts / source.name)\n        self.accepted_helper = hashlib.sha256((scripts / COMMITMENT.name).read_bytes()).hexdigest()\n\n',
)
replace_once(
    private_test,
    '        if accepted_private is not None:\n            environment["NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256"] = accepted_private\n',
    '        if accepted_private is not None:\n            environment["NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256"] = accepted_private\n            environment["NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256"] = self.accepted_helper\n',
)
replace_once(
    private_test,
    '        private = self.digest_from_review(review.stdout, "Private review commitment SHA-256")\n',
    '        private = self.digest_from_review(review.stdout, "Private review commitment SHA-256")\n'
    '        helper = self.digest_from_review(review.stdout, "Private review verifier source SHA-256")\n'
    '        self.assertEqual(helper, self.accepted_helper)\n',
)
replace_once(
    private_test,
    '                "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256": private,\n',
    '                "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256": private,\n'
    '                "NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256": self.accepted_helper,\n',
)

generated_test = Path("scripts/ci/tests/test_capture_cocoapods_generated_build_subject.py")
replace_once(
    generated_test,
    '        for source in (BOOTSTRAP, PROVENANCE, PRIVATE_REVIEW, SUBJECT_HELPER):\n            shutil.copy2(source, scripts / source.name)\n\n',
    '        for source in (BOOTSTRAP, PROVENANCE, PRIVATE_REVIEW, SUBJECT_HELPER):\n            shutil.copy2(source, scripts / source.name)\n        self.accepted_private_review_helper = hashlib.sha256((scripts / PRIVATE_REVIEW.name).read_bytes()).hexdigest()\n\n',
)
replace_once(
    generated_test,
    '        if accepted_private is not None:\n            environment["NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256"] = accepted_private\n',
    '        if accepted_private is not None:\n            environment["NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256"] = accepted_private\n'
    '            environment["NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256"] = self.accepted_private_review_helper\n',
)

print("materialized private-review verifier execution custody")
