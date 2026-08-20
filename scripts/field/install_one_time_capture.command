#!/bin/bash -p
set -euo pipefail

if [[ $- != *p* ]]; then
  builtin printf '%s\n' 'ERROR: open scripts/field/install_one_time_capture.command directly; imported Bash startup state must remain disabled.' >&2
  exit 2
fi

set +x
PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset BASH_ENV ENV CDPATH GLOBIGNORE XCODE_XCCONFIG_FILE OTHER_SWIFT_FLAGS SWIFT_ACTIVE_COMPILATION_CONDITIONS || true

ROOT="$(cd "$(/usr/bin/dirname "$0")/../.." && /bin/pwd -P)"
cd "$ROOT"
umask 077

say() { builtin printf '\n==> %s\n' "$*"; }
die() { builtin printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || die "Run this on the intended field Mac."
[[ -x /usr/bin/python3 ]] || die "System Python 3 is required."
[[ -x /usr/bin/shasum ]] || die "System shasum is required."

# Exact-retained-IPA installer migration checkpoint.
#
# The stable retained-install manifest contract and app-owned authorization adapter now exist, but
# the independently reviewed production trust root and final standalone capability lifecycle do not.
# This checkpoint authenticates and cross-binds only stable pre-install evidence. It deliberately
# does not accept the future challenge-bound authorization envelope, rebuild an app, contact a
# device, install, launch, or grant OFF1. The post-install envelope can exist only after the running
# app creates its fresh process-local challenge.
RETAINED_INSTALL_CONTRACT_STATUS="blocked-missing-pinned-trust-and-standalone-capability-integration"

validate_retained_input() {
  local label="$1"
  local input_path="$2"
  local expected_sha256="$3"
  local access_policy="$4"
  local maximum_bytes="$5"

  [[ "$expected_sha256" =~ ^[0-9A-Fa-f]{64}$ ]] || die "$label expected SHA-256 must be 64 hex characters."
  expected_sha256="$(printf '%s' "$expected_sha256" | /usr/bin/tr '[:upper:]' '[:lower:]')"

  /usr/bin/env -i \
    PATH=/usr/bin:/bin \
    LC_ALL=C \
    /usr/bin/python3 -I -B - \
      "$label" "$input_path" "$expected_sha256" "$access_policy" "$maximum_bytes" <<'PY'
import hashlib
import hmac
import os
import stat
import sys
from pathlib import PurePath

label, raw_path, expected, access_policy, maximum_raw = sys.argv[1:]
if not raw_path.startswith("/") or "\x00" in raw_path:
    raise SystemExit(2)
path = PurePath(raw_path)
if path.parts[0] != "/" or any(part in {"", ".", ".."} for part in path.parts[1:]):
    raise SystemExit(3)
if access_policy not in {"public", "private"}:
    raise SystemExit(4)
try:
    maximum = int(maximum_raw, 10)
except ValueError:
    raise SystemExit(5)
if maximum <= 0:
    raise SystemExit(6)

directory_flags = os.O_RDONLY | os.O_DIRECTORY
no_follow = getattr(os, "O_NOFOLLOW", None)
if no_follow is None:
    raise SystemExit(7)
directory_fd = os.open("/", directory_flags)
try:
    for component in path.parts[1:-1]:
        next_fd = os.open(component, directory_flags | no_follow, dir_fd=directory_fd)
        os.close(directory_fd)
        directory_fd = next_fd
    descriptor = os.open(path.parts[-1], os.O_RDONLY | no_follow, dir_fd=directory_fd)
finally:
    os.close(directory_fd)

try:
    before = os.fstat(descriptor)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise SystemExit(8)
    if hasattr(os, "geteuid") and before.st_uid != os.geteuid():
        raise SystemExit(9)
    forbidden_mode = 0o077 if access_policy == "private" else 0o022
    if stat.S_IMODE(before.st_mode) & forbidden_mode:
        raise SystemExit(10)
    if before.st_size <= 0 or before.st_size > maximum:
        raise SystemExit(11)

    digest = hashlib.sha256()
    byte_count = 0
    while True:
        block = os.read(descriptor, 1024 * 1024)
        if not block:
            break
        digest.update(block)
        byte_count += len(block)
    after = os.fstat(descriptor)
    identity = lambda value: (
        value.st_dev, value.st_ino, value.st_mode, value.st_uid, value.st_nlink,
        value.st_size, value.st_mtime_ns, value.st_ctime_ns,
    )
    if identity(after) != identity(before) or byte_count != before.st_size:
        raise SystemExit(12)
    if not hmac.compare_digest(digest.hexdigest(), expected):
        raise SystemExit(13)
finally:
    os.close(descriptor)
PY
}

run_retained_input_self_test() {
  local test_root test_file test_digest hard_link
  test_root="$(/usr/bin/mktemp -d "/private/tmp/nembra-retained-install-self-test.XXXXXX")"
  [[ "$test_root" == "/private/tmp/nembra-retained-install-self-test."* ]] || die "Self-test temporary path is invalid."
  /bin/chmod 700 "$test_root"
  test_file="$test_root/subject.json"
  builtin printf '%s\n' '{"selfTest":true}' > "$test_file"
  /bin/chmod 600 "$test_file"
  test_digest="$(/usr/bin/shasum -a 256 "$test_file" | /usr/bin/awk '{print $1}')"
  validate_retained_input "self-test subject" "$test_file" "$test_digest" private 1024

  /bin/ln -s "$test_file" "$test_root/substituted.json"
  if validate_retained_input "self-test substituted subject" "$test_root/substituted.json" "$test_digest" private 1024 2>/dev/null; then
    /bin/rm -rf -- "$test_root"
    die "Self-test accepted a symlinked retained subject."
  fi

  hard_link="$test_root/hard-linked.json"
  /bin/ln "$test_file" "$hard_link"
  if validate_retained_input "self-test hard-linked subject" "$hard_link" "$test_digest" private 1024 2>/dev/null; then
    /bin/rm -rf -- "$test_root"
    die "Self-test accepted a multiply linked retained subject."
  fi

  /bin/rm -rf -- "$test_root"
  say "Retained-input no-follow/hash/mode/link self-test passed"
}

case "${1:-}" in
  --self-test)
    [[ "$#" == 1 ]] || die "--self-test accepts no additional arguments."
    run_retained_input_self_test
    exit 0
    ;;
  --dry-run)
    [[ "$#" == 1 ]] || die "--dry-run accepts no additional arguments."
    ;;
  "") ;;
  *) die "Only --dry-run or --self-test is accepted; private values and hashes must not be placed on argv." ;;
esac

: "${NEMBRA_RETAINED_INSTALL_MANIFEST_PATH:?Set NEMBRA_RETAINED_INSTALL_MANIFEST_PATH to the absolute canonical retained-install manifest path.}"
: "${NEMBRA_RETAINED_INSTALL_MANIFEST_SHA256:?Set NEMBRA_RETAINED_INSTALL_MANIFEST_SHA256 to its independently accepted SHA-256.}"
: "${NEMBRA_RETAINED_IPA_PATH:?Set NEMBRA_RETAINED_IPA_PATH to the absolute retained accepted signed IPA path.}"
: "${NEMBRA_RETAINED_IPA_SHA256:?Set NEMBRA_RETAINED_IPA_SHA256 to its independently accepted SHA-256.}"
: "${NEMBRA_ACCEPTED_BUILD_SUBJECT_PATH:?Set NEMBRA_ACCEPTED_BUILD_SUBJECT_PATH to the absolute accepted external build-record path.}"
: "${NEMBRA_ACCEPTED_BUILD_SUBJECT_SHA256:?Set NEMBRA_ACCEPTED_BUILD_SUBJECT_SHA256.}"
: "${NEMBRA_ACCEPTED_EVIDENCE_SUBJECT_PATH:?Set NEMBRA_ACCEPTED_EVIDENCE_SUBJECT_PATH to the absolute accepted signed-build-evidence path.}"
: "${NEMBRA_ACCEPTED_EVIDENCE_SUBJECT_SHA256:?Set NEMBRA_ACCEPTED_EVIDENCE_SUBJECT_SHA256.}"
: "${NEMBRA_ACCEPTED_FINAL_GO_SUBJECT_PATH:?Set NEMBRA_ACCEPTED_FINAL_GO_SUBJECT_PATH to the absolute accepted Final-GO subject path.}"
: "${NEMBRA_ACCEPTED_FINAL_GO_SUBJECT_SHA256:?Set NEMBRA_ACCEPTED_FINAL_GO_SUBJECT_SHA256.}"
: "${NEMBRA_ACCEPTED_TUYA_LOCK_SUBJECT_PATH:?Set NEMBRA_ACCEPTED_TUYA_LOCK_SUBJECT_PATH to the absolute accepted Tuya-lock subject path.}"
: "${NEMBRA_ACCEPTED_TUYA_LOCK_SUBJECT_SHA256:?Set NEMBRA_ACCEPTED_TUYA_LOCK_SUBJECT_SHA256.}"
: "${NEMBRA_INTENDED_DEVICE_PSEUDONYMOUS_BINDING_PATH:?Set NEMBRA_INTENDED_DEVICE_PSEUDONYMOUS_BINDING_PATH to its absolute private path.}"
: "${NEMBRA_INTENDED_DEVICE_PSEUDONYMOUS_BINDING_SHA256:?Set NEMBRA_INTENDED_DEVICE_PSEUDONYMOUS_BINDING_SHA256.}"

validate_retained_input "retained install manifest" "$NEMBRA_RETAINED_INSTALL_MANIFEST_PATH" "$NEMBRA_RETAINED_INSTALL_MANIFEST_SHA256" private 16384
validate_retained_input "retained accepted signed IPA" "$NEMBRA_RETAINED_IPA_PATH" "$NEMBRA_RETAINED_IPA_SHA256" public 1073741824
validate_retained_input "accepted external build record" "$NEMBRA_ACCEPTED_BUILD_SUBJECT_PATH" "$NEMBRA_ACCEPTED_BUILD_SUBJECT_SHA256" public 16777216
validate_retained_input "accepted signed build evidence" "$NEMBRA_ACCEPTED_EVIDENCE_SUBJECT_PATH" "$NEMBRA_ACCEPTED_EVIDENCE_SUBJECT_SHA256" public 16777216
validate_retained_input "accepted Final-GO subject" "$NEMBRA_ACCEPTED_FINAL_GO_SUBJECT_PATH" "$NEMBRA_ACCEPTED_FINAL_GO_SUBJECT_SHA256" private 16777216
validate_retained_input "accepted Tuya-lock subject" "$NEMBRA_ACCEPTED_TUYA_LOCK_SUBJECT_PATH" "$NEMBRA_ACCEPTED_TUYA_LOCK_SUBJECT_SHA256" public 4194304
validate_retained_input "intended-device pseudonymous binding" "$NEMBRA_INTENDED_DEVICE_PSEUDONYMOUS_BINDING_PATH" "$NEMBRA_INTENDED_DEVICE_PSEUDONYMOUS_BINDING_SHA256" private 1048576
say "Exact stable pre-install bytes passed bounded path/hash/mode admission"

# Cross-binding is still evidence-only. The helper is executed from this accepted checkout solely to
# compare already-admitted stable bytes; a successful comparison cannot install, launch, contact a
# device, select a key, create the post-install envelope, or grant OFF1.
if ! /usr/bin/env -i \
  PATH=/usr/bin:/bin \
  LC_ALL=C \
  NEMBRA_ROOT="$ROOT" \
  NEMBRA_RETAINED_INSTALL_MANIFEST_PATH="$NEMBRA_RETAINED_INSTALL_MANIFEST_PATH" \
  NEMBRA_RETAINED_INSTALL_MANIFEST_SHA256="$NEMBRA_RETAINED_INSTALL_MANIFEST_SHA256" \
  NEMBRA_RETAINED_IPA_SHA256="$NEMBRA_RETAINED_IPA_SHA256" \
  NEMBRA_ACCEPTED_BUILD_SUBJECT_PATH="$NEMBRA_ACCEPTED_BUILD_SUBJECT_PATH" \
  NEMBRA_ACCEPTED_BUILD_SUBJECT_SHA256="$NEMBRA_ACCEPTED_BUILD_SUBJECT_SHA256" \
  NEMBRA_ACCEPTED_EVIDENCE_SUBJECT_PATH="$NEMBRA_ACCEPTED_EVIDENCE_SUBJECT_PATH" \
  NEMBRA_ACCEPTED_EVIDENCE_SUBJECT_SHA256="$NEMBRA_ACCEPTED_EVIDENCE_SUBJECT_SHA256" \
  NEMBRA_ACCEPTED_FINAL_GO_SUBJECT_PATH="$NEMBRA_ACCEPTED_FINAL_GO_SUBJECT_PATH" \
  NEMBRA_ACCEPTED_FINAL_GO_SUBJECT_SHA256="$NEMBRA_ACCEPTED_FINAL_GO_SUBJECT_SHA256" \
  NEMBRA_ACCEPTED_TUYA_LOCK_SUBJECT_SHA256="$NEMBRA_ACCEPTED_TUYA_LOCK_SUBJECT_SHA256" \
  NEMBRA_INTENDED_DEVICE_PSEUDONYMOUS_BINDING_SHA256="$NEMBRA_INTENDED_DEVICE_PSEUDONYMOUS_BINDING_SHA256" \
  /usr/bin/python3 -I -B - <<'PY'
import importlib.util
import os
from pathlib import Path

root = Path(os.environ["NEMBRA_ROOT"])
helper_path = root / "scripts/ci/es80_retained_install_cross_binding.py"
spec = importlib.util.spec_from_file_location("nembra_retained_install_cross_binding", helper_path)
if spec is None or spec.loader is None:
    raise RuntimeError("retained-install cross-binding helper is unavailable")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

read = lambda name: Path(os.environ[name]).read_bytes()
helper.verify_cross_binding(
    install_manifest_data=read("NEMBRA_RETAINED_INSTALL_MANIFEST_PATH"),
    external_build_record_data=read("NEMBRA_ACCEPTED_BUILD_SUBJECT_PATH"),
    signed_build_evidence_data=read("NEMBRA_ACCEPTED_EVIDENCE_SUBJECT_PATH"),
    final_go_record_data=read("NEMBRA_ACCEPTED_FINAL_GO_SUBJECT_PATH"),
    accepted_install_manifest_sha256=os.environ["NEMBRA_RETAINED_INSTALL_MANIFEST_SHA256"].lower(),
    accepted_retained_ipa_sha256=os.environ["NEMBRA_RETAINED_IPA_SHA256"].lower(),
    accepted_external_build_record_sha256=os.environ["NEMBRA_ACCEPTED_BUILD_SUBJECT_SHA256"].lower(),
    accepted_signed_build_evidence_sha256=os.environ["NEMBRA_ACCEPTED_EVIDENCE_SUBJECT_SHA256"].lower(),
    accepted_final_go_record_sha256=os.environ["NEMBRA_ACCEPTED_FINAL_GO_SUBJECT_SHA256"].lower(),
    accepted_tuya_lock_sha256=os.environ["NEMBRA_ACCEPTED_TUYA_LOCK_SUBJECT_SHA256"].lower(),
    accepted_intended_device_pseudonym_sha256=os.environ[
        "NEMBRA_INTENDED_DEVICE_PSEUDONYMOUS_BINDING_SHA256"
    ].lower(),
)
PY
then
  die "Retained install manifest does not cross-bind the independently accepted stable subjects."
fi

say "Retained manifest cross-bound the accepted stable install/evidence tuple"
die "Installation remains blocked: production trust-root review and standalone opaque-capability lifecycle integration are incomplete. No app was rebuilt, contacted, installed, launched, or authorized for OFF1. Status: $RETAINED_INSTALL_CONTRACT_STATUS"
