from pathlib import Path

path = Path("scripts/field/install_one_time_capture.command")
source = path.read_text(encoding="utf-8")
anchor = '''[[ "$NEMBRA_ACCEPTED_SOURCE_COMMIT_SHA" != "0000000000000000000000000000000000000000" ]] || die "NEMBRA_ACCEPTED_SOURCE_COMMIT_SHA cannot be the zero SHA."\n'''
if source.count(anchor) != 1:
    raise SystemExit(f"accepted-source insertion anchor count was {source.count(anchor)}; refusing")

block = r'''
SOURCE_SHA="$NEMBRA_ACCEPTED_SOURCE_COMMIT_SHA"

# Capture every nested repository tool from the independently accepted Git commit before any
# later authority-bearing execution. A mutable checkout pathname may provide product context, but
# it can never select the bytes that execute. This seam creates no device/install/Bluetooth
# authority; the PRE-INSTALL hard stop below remains authoritative until separately accepted.
capture_accepted_git_source_base64() {
  local relative_path="$1"
  local resolved_source blob source_b64 measured_blob
  [[ -n "$relative_path" && "$relative_path" != /* && "$relative_path" != *".."* ]] || die "Accepted Git source path is invalid."

  resolved_source="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git -C "$ROOT" rev-parse --verify "$SOURCE_SHA^{commit}" 2>/dev/null)" || \
    die "Independently accepted source commit could not be resolved."
  [[ "$resolved_source" == "$SOURCE_SHA" ]] || die "Accepted Git source resolved to a different commit."

  blob="$(GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git -C "$ROOT" rev-parse "$SOURCE_SHA:$relative_path" 2>/dev/null)" || \
    die "Accepted nested repository tool is missing from the exact source commit: $relative_path"
  [[ "$blob" =~ ^[0-9a-f]{40}$ ]] || die "Accepted nested repository tool Git blob is malformed: $relative_path"

  source_b64="$(GIT_NO_REPLACE_OBJECTS=1 git -C "$ROOT" cat-file blob "$blob" | /usr/bin/base64 | /usr/bin/tr -d '\n')" || \
    die "Accepted nested repository tool could not be captured: $relative_path"
  [[ -n "$source_b64" ]] || die "Accepted nested repository tool capture is empty: $relative_path"

  measured_blob="$(
    printf '%s' "$source_b64" |
      /usr/bin/python3 -c 'import base64,sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.buffer.read(), validate=True))' |
      GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git -C "$ROOT" hash-object --stdin
  )" || die "Accepted nested repository tool capture could not be re-hashed: $relative_path"
  [[ "$measured_blob" == "$blob" ]] || die "Captured nested repository tool bytes do not match the accepted Git object: $relative_path"
  printf '%s' "$source_b64"
}

CAPTURE_BOOTSTRAP_PATH="Scripts/bootstrap_capture_tuya_sdk.sh"
TUYA_PROVENANCE_PATH="Scripts/capture_tuya_private_input_provenance.py"
PRIVATE_DEVICE_RUNNER_PATH="scripts/ci/es80_signed_field_artifact_private_runner.py"
CAPTURE_BOOTSTRAP_SOURCE_B64="$(capture_accepted_git_source_base64 "$CAPTURE_BOOTSTRAP_PATH")"
TUYA_PROVENANCE_SOURCE_B64="$(capture_accepted_git_source_base64 "$TUYA_PROVENANCE_PATH")"
PRIVATE_DEVICE_RUNNER="$(capture_accepted_git_source_base64 "$PRIVATE_DEVICE_RUNNER_PATH")"

# These adapters consume only the already captured bytes. The present pre-install checkpoint does
# not invoke them; they are the closed execution handoff for a separately accepted field rung.
run_accepted_capture_bootstrap() {
  printf '%s' "$CAPTURE_BOOTSTRAP_SOURCE_B64" | /usr/bin/base64 -D | /bin/bash -p -s -- \
    --field-repo-root "$ROOT" \
    --field-source-sha "$SOURCE_SHA" \
    --field-provenance-helper-base64 "$TUYA_PROVENANCE_SOURCE_B64"
}

run_accepted_tuya_provenance() {
  local operation="$1"
  shift
  /usr/bin/python3 -I -B - "$TUYA_PROVENANCE_SOURCE_B64" "$operation" "$@" <<'PY'
import base64
import sys

source = base64.b64decode(sys.argv[1], validate=True)
operation = sys.argv[2]
arguments = sys.argv[3:]
namespace = {"__name__": "__main__", "__file__": "<accepted-tuya-provenance-helper>"}
sys.argv = ["<accepted-tuya-provenance-helper>", operation, *arguments]
exec(compile(source, namespace["__file__"], "exec", dont_inherit=True), namespace)
PY
}

run_accepted_private_device_reader() {
  /usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER" "$@" <<'PY'
import base64
import sys

source = base64.b64decode(sys.argv[1], validate=True)
namespace = {"__name__": "nembra_private_device_reader", "__file__": "<accepted-private-device-runner>"}
exec(compile(source, namespace["__file__"], "exec", dont_inherit=True), namespace)
reader = namespace.get("read_private_identifier")
if not callable(reader):
    raise RuntimeError("accepted private intended-device reader does not expose read_private_identifier")
PY
}
'''

source = source.replace(anchor, anchor + block, 1)
path.write_text(source, encoding="utf-8")
