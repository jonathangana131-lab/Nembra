#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / ".github/workflows/capture-field-build-provenance.yml"
EXPECTED_BLOB = "5fb480ab0401fc91e0986141094d67853f9f1852"


def git_blob(payload: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload).hexdigest()


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return source.replace(old, new, 1)

payload = TARGET.read_bytes()
actual = git_blob(payload)
if actual != EXPECTED_BLOB:
    raise SystemExit(f"workflow moved: expected {EXPECTED_BLOB}, got {actual}")

source = payload.decode("utf-8")
source = replace_once(
    source,
    '''          grep -Fq 'SOURCE_SHA="$(git rev-parse HEAD | tr ' "$installer"\n          grep -Fq '[[ "$SOURCE_SHA" == "$EXPECTED_SOURCE_SHA" ]]' "$installer"\n          grep -Fq 'Current checkout $SOURCE_SHA does not match accepted Capture source $EXPECTED_SOURCE_SHA' "$installer"\n          grep -Fq 'Exact requested Capture source matched: $SOURCE_SHA' "$installer"\n''',
    '''          grep -Fq 'AUTHORITY_GIT_DIR="$ROOT/.git"' "$installer"\n          grep -Fq 'run_authority_git() {' "$installer"\n          grep -Fq 'GIT_NO_REPLACE_OBJECTS=1' "$installer"\n          grep -Fq 'SOURCE_SHA="$(run_authority_git rev-parse --verify' "$installer"\n          grep -Fq '[[ "$SOURCE_SHA" == "$EXPECTED_SOURCE_SHA" ]]' "$installer"\n          grep -Fq 'verify_accepted_checkout_source() {' "$installer"\n          grep -Fq 'status --porcelain=v1 --untracked-files=no' "$installer"\n          grep -Fq 'Raw accepted-source byte audit failed.' "$installer"\n          grep -Fq 'verify_accepted_checkout_source "Current checkout is not the exact accepted Capture source."' "$installer"\n          grep -Fq 'Current checkout $SOURCE_SHA does not match accepted Capture source $EXPECTED_SOURCE_SHA' "$installer"\n          grep -Fq 'Exact requested Capture source matched under isolated Git + raw-byte authority: $SOURCE_SHA' "$installer"\n          grep -Fq 'run_accepted_source_bash "Scripts/bootstrap_capture_tuya_sdk.sh"' "$installer"\n          if grep -Fq '"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh"' "$installer"; then\n            echo 'ERROR: bootstrap must execute from accepted Git-object bytes, not mutable checkout bytes.' >&2\n            exit 1\n          fi\n''',
    "source authority contract",
)
source = replace_once(
    source,
    '''          build_line="$(grep -nF -- '-- xcodebuild \\' "$installer" | sed -n '1s/:.*//p')"\n''',
    '''          build_line="$(grep -nF -- '-- /usr/bin/xcodebuild \\' "$installer" | sed -n '1s/:.*//p')"\n''',
    "absolute xcodebuild ordering contract",
)
TARGET.write_text(source, encoding="utf-8")
