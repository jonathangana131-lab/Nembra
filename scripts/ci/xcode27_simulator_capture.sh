#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT/Artifacts/Xcode27Simulator}"
DERIVED_DATA="${DERIVED_DATA:-${RUNNER_TEMP:-/tmp}/NembraDerivedData}"
RESULT_BUNDLE="$ARTIFACTS_DIR/NembraTests.xcresult"
ATTACHMENTS_DIR="$ARTIFACTS_DIR/test-attachments"
BUILD_EVIDENCE_DIR="$ARTIFACTS_DIR/build-evidence"
BUNDLE_ID="com.jonathangana131.nembra"

CAPTURE_BUILD_COMMIT_SHA="$(git rev-parse --verify HEAD^{commit})"
if [[ ! "$CAPTURE_BUILD_COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Capture build identity requires an exact 40-hex Git commit; got: $CAPTURE_BUILD_COMMIT_SHA" >&2
  exit 8
fi

# Exact source identity must cover every non-ignored file that could enter the build. SwiftPM and
# Xcode can discover an untracked source under synchronized/package source roots, so checking only
# tracked modifications would allow HEAD to look exact while the binary contains code outside Git.
# Run this before creating the QA artifact directory so runner output cannot contaminate the check.
REPOSITORY_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
if [[ -n "$REPOSITORY_STATUS" ]]; then
  echo "Capture build identity refuses tracked changes or non-ignored untracked files." >&2
  printf '%s\n' "$REPOSITORY_STATUS" >&2
  exit 9
fi

# Ignored output from an older local/self-hosted run must never be mixed into exact-head acceptance.
# Refuse reuse instead of deleting it: existing evidence may itself be valuable and should not be
# silently destroyed merely because a later run chose the same destination.
if [[ -e "$ARTIFACTS_DIR" || -L "$ARTIFACTS_DIR" ]]; then
  echo "ARTIFACTS_DIR already exists; refusing to mix or overwrite Simulator evidence: $ARTIFACTS_DIR" >&2
  exit 22
fi
ARTIFACTS_PARENT="$(dirname "$ARTIFACTS_DIR")"
mkdir -p "$ARTIFACTS_PARENT"
mkdir "$ARTIFACTS_DIR"
mkdir "$ARTIFACTS_DIR/screenshots" "$ARTIFACTS_DIR/logs" "$ATTACHMENTS_DIR" "$BUILD_EVIDENCE_DIR"

CAPTURE_BUILD_IDENTIFIER="Capture Build V14-${CAPTURE_BUILD_COMMIT_SHA:0:12}"
CAPTURE_BUILD_INSTANCE_ID="$(python3 -c 'import uuid; print(str(uuid.uuid4()))')"
if [[ ! "$CAPTURE_BUILD_INSTANCE_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "Capture build instance must be one canonical lowercase UUID; got: $CAPTURE_BUILD_INSTANCE_ID" >&2
  exit 15
fi
CAPTURE_RECIPE_IDENTIFIER="ES80-FINGERPRINT-v1"
CAPTURE_PROCEDURE_VERSION="V14"

{
  echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "runner_arch=$(uname -m)"
  echo "capture_build_identifier=$CAPTURE_BUILD_IDENTIFIER"
  echo "capture_build_instance_id=$CAPTURE_BUILD_INSTANCE_ID"
  echo "capture_build_commit_sha=$CAPTURE_BUILD_COMMIT_SHA"
  echo "capture_recipe_identifier=$CAPTURE_RECIPE_IDENTIFIER"
  echo "capture_procedure_version=$CAPTURE_PROCEDURE_VERSION"
  sw_vers
  xcodebuild -version
  xcrun simctl list runtimes
  xcrun simctl list devicetypes
} > "$ARTIFACTS_DIR/environment.txt"

RUNTIME_ID="$({ xcrun simctl list runtimes -j | python3 -c '
import json,sys
r=json.load(sys.stdin)["runtimes"]
c=[x for x in r if x.get("isAvailable", True) and str(x.get("identifier", "")).startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")]
if not c: raise SystemExit(1)
c.sort(key=lambda x: tuple(int(p) for p in str(x.get("version","0")).split(".") if p.isdigit()), reverse=True)
print(c[0]["identifier"])
'; } 2>/dev/null)" || {
  echo "No iOS 27 Simulator runtime is available on this runner." >&2
  exit 2
}

DEVICE_TYPE="$({ xcrun simctl list devicetypes -j | python3 -c '
import json,sys
items=json.load(sys.stdin)["devicetypes"]
preferred=["iPhone 12", "iPhone 17", "iPhone 17 Pro", "iPhone 16"]
for name in preferred:
    for x in items:
        if x.get("name")==name:
            print(x["identifier"]); raise SystemExit(0)
raise SystemExit(1)
'; } 2>/dev/null)" || {
  echo "No supported iPhone Simulator device type found." >&2
  exit 3
}

SIM_NAME="Nembra Xcode27 CI ${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"
UDID="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")"
cleanup() {
  xcrun simctl spawn "$UDID" log show --last 10m --style compact --predicate 'process == "Nembra"' \
    > "$ARTIFACTS_DIR/logs/nembra-system.log" 2>&1 || true
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "runtime=$RUNTIME_ID" >> "$ARTIFACTS_DIR/environment.txt"
echo "device_type=$DEVICE_TYPE" >> "$ARTIFACTS_DIR/environment.txt"
echo "simulator_udid=$UDID" >> "$ARTIFACTS_DIR/environment.txt"

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b

set +e
set -o pipefail
xcodebuild \
  -project Nembra.xcodeproj \
  -scheme Nembra \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 120 \
  -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO \
  "INFOPLIST_KEY_NembraCaptureBuildIdentifier=$CAPTURE_BUILD_IDENTIFIER" \
  "INFOPLIST_KEY_NembraCaptureBuildInstanceID=$CAPTURE_BUILD_INSTANCE_ID" \
  "INFOPLIST_KEY_NembraCaptureBuildCommitSHA=$CAPTURE_BUILD_COMMIT_SHA" \
  test \
  | tee "$ARTIFACTS_DIR/logs/xcodebuild-test.log"
TEST_STATUS=${PIPESTATUS[0]}
set -e

if [[ -d "$RESULT_BUNDLE" ]]; then
  if xcrun xcresulttool export attachments \
    --path "$RESULT_BUNDLE" \
    --output-path "$ATTACHMENTS_DIR" \
    > "$ARTIFACTS_DIR/logs/xcresult-attachments.log" 2>&1; then
    find "$ATTACHMENTS_DIR" -type f -maxdepth 2 -print | sort \
      > "$ARTIFACTS_DIR/test-attachments.txt" || true
  else
    {
      echo "Attachment export failed; the complete xcresult is still preserved."
      xcrun xcresulttool help export attachments || true
    } >> "$ARTIFACTS_DIR/logs/xcresult-attachments.log" 2>&1
  fi
fi

if [[ "$TEST_STATUS" -ne 0 ]]; then
  echo "xcodebuild test failed with status $TEST_STATUS; preserving diagnostics before failing the job." >&2
  exit "$TEST_STATUS"
fi

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Nembra.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected built app was not found at $APP_PATH" >&2
  find "$DERIVED_DATA/Build/Products" -name 'Nembra.app' -print >&2 || true
  exit 4
fi

INFO_PLIST="$APP_PATH/Info.plist"
EMBEDDED_BUILD_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :NembraCaptureBuildIdentifier' "$INFO_PLIST" 2>/dev/null || true)"
EMBEDDED_BUILD_INSTANCE_ID="$(/usr/libexec/PlistBuddy -c 'Print :NembraCaptureBuildInstanceID' "$INFO_PLIST" 2>/dev/null || true)"
EMBEDDED_BUILD_COMMIT_SHA="$(/usr/libexec/PlistBuddy -c 'Print :NembraCaptureBuildCommitSHA' "$INFO_PLIST" 2>/dev/null || true)"
if [[ "$EMBEDDED_BUILD_IDENTIFIER" != "$CAPTURE_BUILD_IDENTIFIER" ]]; then
  echo "Built app did not preserve the exact Capture build identifier." >&2
  exit 10
fi
if [[ "$EMBEDDED_BUILD_INSTANCE_ID" != "$CAPTURE_BUILD_INSTANCE_ID" ]]; then
  echo "Built app did not preserve the exact Capture build-instance identifier." >&2
  exit 16
fi
if [[ "$EMBEDDED_BUILD_COMMIT_SHA" != "$CAPTURE_BUILD_COMMIT_SHA" ]]; then
  echo "Built app did not preserve the exact Capture source commit SHA." >&2
  exit 11
fi

EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
EXECUTABLE_PATH="$APP_PATH/$EXECUTABLE_NAME"
if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  echo "Expected built executable was not found at $EXECUTABLE_PATH" >&2
  exit 12
fi
EXECUTABLE_SHA256="$(shasum -a 256 "$EXECUTABLE_PATH" | awk '{print $1}')"
if [[ ! "$EXECUTABLE_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Could not derive a valid SHA-256 digest for the built executable." >&2
  exit 13
fi
INFO_PLIST_SHA256="$(shasum -a 256 "$INFO_PLIST" | awk '{print $1}')"
if [[ ! "$INFO_PLIST_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Could not derive a valid SHA-256 digest for the built Info.plist." >&2
  exit 17
fi

# Retain the exact bytes whose identity is asserted by the external provenance record. A digest
# alone is useful, but preserving these immutable copies lets a later reviewer independently
# re-hash the same executable and inspect the exact generated build metadata after DerivedData is
# gone. This is Simulator software evidence only; the physical pipeline must retain the exact final
# signed field artifact (for example the accepted .ipa) rather than substituting these bytes.
RETAINED_EXECUTABLE="$BUILD_EVIDENCE_DIR/Nembra"
RETAINED_INFO_PLIST="$BUILD_EVIDENCE_DIR/Info.plist"
cp -p "$EXECUTABLE_PATH" "$RETAINED_EXECUTABLE"
cp -p "$INFO_PLIST" "$RETAINED_INFO_PLIST"
if ! cmp -s "$EXECUTABLE_PATH" "$RETAINED_EXECUTABLE"; then
  echo "Retained Capture executable bytes diverged from the measured build output." >&2
  exit 18
fi
if ! cmp -s "$INFO_PLIST" "$RETAINED_INFO_PLIST"; then
  echo "Retained Capture Info.plist bytes diverged from the measured build output." >&2
  exit 19
fi
RETAINED_EXECUTABLE_SHA256="$(shasum -a 256 "$RETAINED_EXECUTABLE" | awk '{print $1}')"
RETAINED_INFO_PLIST_SHA256="$(shasum -a 256 "$RETAINED_INFO_PLIST" | awk '{print $1}')"
if [[ "$RETAINED_EXECUTABLE_SHA256" != "$EXECUTABLE_SHA256" ]]; then
  echo "Retained Capture executable digest does not match the measured build output." >&2
  exit 20
fi
if [[ "$RETAINED_INFO_PLIST_SHA256" != "$INFO_PLIST_SHA256" ]]; then
  echo "Retained Capture Info.plist digest does not match the measured build output." >&2
  exit 21
fi

# Keep the exact-executable digest record OUTSIDE the app bundle.
#
# On a signed Apple-platform app, bundle resources participate in the code-signing resource seal,
# while the code signature itself is stored in the Mach-O executable. Embedding a resource that
# contains the hash of the final signed executable would therefore create a self-reference loop:
# the record changes the resource seal/signature, which changes the executable digest recorded by
# that same resource. Simulator uses CODE_SIGNING_ALLOWED=NO, but this harness must not normalize a
# topology that cannot truthfully carry over to the final physical-device build.
#
# `buildInstanceID` is generated before the build and embedded in the app, then repeated in this
# external post-build record. It is an opaque rendezvous identifier, not an attestation by itself.
# The workflow attestation over this exact record is what gives the external record independent
# provenance without feeding its final executable digest back into the signed app.
EXTERNAL_BUILD_RECORD="$ARTIFACTS_DIR/NembraCaptureExternalBuildRecord.json"
RUNNER_METADATA="$ARTIFACTS_DIR/capture-runner-metadata.json"
python3 - \
  "$EXTERNAL_BUILD_RECORD" \
  "$RUNNER_METADATA" \
  "$CAPTURE_BUILD_IDENTIFIER" \
  "$CAPTURE_BUILD_INSTANCE_ID" \
  "$CAPTURE_BUILD_COMMIT_SHA" \
  "$EXECUTABLE_SHA256" \
  "$INFO_PLIST_SHA256" \
  "$CAPTURE_RECIPE_IDENTIFIER" \
  "$CAPTURE_PROCEDURE_VERSION" \
  "$BUNDLE_ID" \
  "${GITHUB_RUN_ID:-local}" \
  "${GITHUB_RUN_ATTEMPT:-0}" <<'PY'
import hashlib
import json
import sys

(
    external_record_path,
    runner_metadata_path,
    build_identifier,
    build_instance_id,
    source_commit_sha,
    executable_sha256,
    info_plist_sha256,
    recipe_identifier,
    procedure_version,
    bundle_identifier,
    run_id,
    run_attempt,
) = sys.argv[1:]

external_record = {
    "schemaVersion": 3,
    "buildIdentifier": build_identifier,
    "buildInstanceID": build_instance_id,
    "sourceCommitSHA": source_commit_sha,
    "executableSHA256": executable_sha256,
    "infoPlistSHA256": info_plist_sha256,
    "experimentRecipeID": recipe_identifier,
    "procedureVersion": procedure_version,
}
external_bytes = (
    json.dumps(external_record, indent=2, sort_keys=True).encode("utf-8") + b"\n"
)
with open(external_record_path, "wb") as handle:
    handle.write(external_bytes)

runner_metadata = {
    "schemaVersion": 1,
    "authority": "external-runner-simulator-provenance-not-field-authorization",
    "externalBuildRecordSHA256": hashlib.sha256(external_bytes).hexdigest(),
    "buildInstanceID": build_instance_id,
    "bundleIdentifier": bundle_identifier,
    "platform": "iOS Simulator",
    "githubRunID": run_id,
    "githubRunAttempt": run_attempt,
}
with open(runner_metadata_path, "w", encoding="utf-8") as handle:
    json.dump(runner_metadata, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

EXTERNAL_BUILD_RECORD_SHA256="$(shasum -a 256 "$EXTERNAL_BUILD_RECORD" | awk '{print $1}')"

printf '%s\n' \
  "capture_executable_sha256=$EXECUTABLE_SHA256" \
  "capture_info_plist_sha256=$INFO_PLIST_SHA256" \
  "capture_retained_executable=$RETAINED_EXECUTABLE" \
  "capture_retained_info_plist=$RETAINED_INFO_PLIST" \
  "capture_external_build_record=$EXTERNAL_BUILD_RECORD" \
  "capture_external_build_record_sha256=$EXTERNAL_BUILD_RECORD_SHA256" \
  "capture_runner_metadata=$RUNNER_METADATA" \
  >> "$ARTIFACTS_DIR/environment.txt"

# Assert the final Simulator app was not mutated with a self-referential executable-digest record.
if [[ -e "$APP_PATH/NembraCaptureTrustedBuildRecord.json" || -e "$APP_PATH/NembraCaptureExternalBuildRecord.json" ]]; then
  echo "Executable-digest provenance record must remain external to the built app bundle." >&2
  exit 14
fi

xcrun simctl install "$UDID" "$APP_PATH"

xcrun simctl status_bar "$UDID" override \
  --time 9:41 \
  --batteryState charged \
  --batteryLevel 82 \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4 >/dev/null 2>&1 || true

capture_state() {
  local state="$1"
  local appearance="${2:-light}"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" appearance "$appearance" >/dev/null 2>&1 || true
  local launch_output pid screenshot_path
  launch_output="$(
    SIMCTL_CHILD_NEMBRA_SIMULATION_SCENARIO="$state" \
      xcrun simctl launch "$UDID" "$BUNDLE_ID" \
      | tee "$ARTIFACTS_DIR/logs/launch-${state}-${appearance}.log"
  )"
  pid="${launch_output##*: }"
  if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
    echo "Could not parse launched Nembra process ID from: $launch_output" >&2
    exit 5
  fi

  sleep 2
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "Nembra exited before ${state}/${appearance} screenshot capture." >&2
    exit 6
  fi

  screenshot_path="$ARTIFACTS_DIR/screenshots/${state}-${appearance}.png"
  xcrun simctl io "$UDID" screenshot "$screenshot_path"
  if [[ ! -s "$screenshot_path" ]]; then
    echo "Simulator screenshot was not created for ${state}/${appearance}." >&2
    exit 7
  fi
}

for state in \
  cold-disconnected \
  reconnecting \
  connected-stopped \
  riding \
  low-battery \
  bluetooth-off \
  permission-denied \
  scooter-unavailable \
  unsupported-configuration
do
  capture_state "$state" light
done
capture_state connected-stopped dark
capture_state reconnecting dark

printf '%s\n' "Captured screenshots:" > "$ARTIFACTS_DIR/screenshots.txt"
find "$ARTIFACTS_DIR/screenshots" -type f -name '*.png' -print | sort >> "$ARTIFACTS_DIR/screenshots.txt"

# Bind every retained visual/test attachment byte to this exact Simulator build without promoting
# screenshots into physical or protocol authority. Open the fresh evidence root once, walk child
# ancestry with no-follow directory descriptors, and hash each regular file from the exact opened
# descriptor whose identity/size is re-proved after the read. The manifest itself is created through
# that same root descriptor and remains Simulator-only evidence.
VISUAL_EVIDENCE_MANIFEST="$ARTIFACTS_DIR/NembraCaptureSimulatorVisualEvidence.json"
python3 - \
  "$VISUAL_EVIDENCE_MANIFEST" \
  "$ARTIFACTS_DIR" \
  "$CAPTURE_BUILD_IDENTIFIER" \
  "$CAPTURE_BUILD_INSTANCE_ID" \
  "$CAPTURE_BUILD_COMMIT_SHA" \
  "$EXTERNAL_BUILD_RECORD_SHA256" <<'PY'
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

(
    manifest_path_text,
    artifacts_root_text,
    build_identifier,
    build_instance_id,
    source_commit_sha,
    external_build_record_sha256,
) = sys.argv[1:]

artifacts_root = Path(artifacts_root_text).resolve()
manifest_path = Path(manifest_path_text).resolve()
if manifest_path.parent != artifacts_root:
    raise SystemExit("visual evidence manifest must remain directly under the fresh artifact root")

if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
    raise SystemExit("platform cannot enforce descriptor-bound visual-evidence ancestry")

NOFOLLOW = os.O_NOFOLLOW
DIRECTORY = os.O_DIRECTORY


def stable_identity(metadata):
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def hash_regular_file(directory_fd: int, name: str) -> tuple[int, str]:
    descriptor = os.open(name, os.O_RDONLY | NOFOLLOW, dir_fd=directory_fd)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise SystemExit(f"visual evidence subject is not a regular file: {name}")
        if before.st_size <= 0:
            raise SystemExit(f"visual evidence manifest refuses empty retained evidence file: {name}")

        os.lseek(descriptor, 0, os.SEEK_SET)
        digest = hashlib.sha256()
        with os.fdopen(os.dup(descriptor), "rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)

        after = os.fstat(descriptor)
        if stable_identity(after) != stable_identity(before):
            raise SystemExit(f"visual evidence subject changed while hashing: {name}")

        try:
            named_after = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        except OSError as exc:
            raise SystemExit(f"visual evidence subject disappeared after hashing: {name}") from exc
        if stable_identity(named_after) != stable_identity(after):
            raise SystemExit(f"visual evidence pathname no longer names the hashed subject: {name}")

        return before.st_size, digest.hexdigest()
    finally:
        os.close(descriptor)


def collect_files(directory_fd: int, relative_prefix: str, artifact_kind: str, entries: list[dict]) -> None:
    with os.scandir(directory_fd) as iterator:
        names = sorted(entry.name for entry in iterator)

    for name in names:
        if name in (".", "..") or "/" in name:
            raise SystemExit(f"visual evidence contains malformed directory entry: {name!r}")
        try:
            metadata = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        except OSError as exc:
            raise SystemExit(f"could not inspect visual evidence entry: {relative_prefix}/{name}") from exc
        relative_path = f"{relative_prefix}/{name}"

        if stat.S_ISLNK(metadata.st_mode):
            raise SystemExit(f"visual evidence must not contain symlinks: {relative_path}")
        if stat.S_ISDIR(metadata.st_mode):
            child_fd = os.open(name, os.O_RDONLY | DIRECTORY | NOFOLLOW, dir_fd=directory_fd)
            try:
                opened = os.fstat(child_fd)
                if not stat.S_ISDIR(opened.st_mode):
                    raise SystemExit(f"visual evidence directory changed during open: {relative_path}")
                collect_files(child_fd, relative_path, artifact_kind, entries)
            finally:
                os.close(child_fd)
            continue
        if not stat.S_ISREG(metadata.st_mode):
            raise SystemExit(f"visual evidence contains unsupported file type: {relative_path}")

        byte_count, digest = hash_regular_file(directory_fd, name)
        entries.append({
            "artifactKind": artifact_kind,
            "relativePath": relative_path,
            "byteCount": byte_count,
            "sha256": digest,
        })


root_fd = os.open(artifacts_root, os.O_RDONLY | DIRECTORY | NOFOLLOW)
try:
    root_metadata = os.fstat(root_fd)
    if not stat.S_ISDIR(root_metadata.st_mode):
        raise SystemExit("fresh Simulator artifact root is not a directory")

    entries = []
    for artifact_kind, relative_root in (
        ("simulatorScreenshot", "screenshots"),
        ("xctestAttachment", "test-attachments"),
    ):
        try:
            child_fd = os.open(
                relative_root,
                os.O_RDONLY | DIRECTORY | NOFOLLOW,
                dir_fd=root_fd,
            )
        except FileNotFoundError:
            continue
        try:
            child_metadata = os.fstat(child_fd)
            if not stat.S_ISDIR(child_metadata.st_mode):
                raise SystemExit(f"visual evidence root is not a directory: {relative_root}")
            collect_files(child_fd, relative_root, artifact_kind, entries)
        finally:
            os.close(child_fd)

    entries.sort(key=lambda entry: (entry["artifactKind"], entry["relativePath"]))
    screenshot_entries = [entry for entry in entries if entry["artifactKind"] == "simulatorScreenshot"]
    if not screenshot_entries:
        raise SystemExit("visual evidence manifest requires at least one retained Simulator screenshot")

    manifest = {
        "schemaVersion": 1,
        "authority": "simulator-visual-evidence-not-physical-authorization",
        "buildIdentifier": build_identifier,
        "buildInstanceID": build_instance_id,
        "sourceCommitSHA": source_commit_sha,
        "externalBuildRecordSHA256": external_build_record_sha256,
        "files": entries,
    }
    manifest_bytes = json.dumps(manifest, indent=2, sort_keys=True).encode("utf-8") + b"\n"

    manifest_fd = os.open(
        manifest_path.name,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | NOFOLLOW,
        0o600,
        dir_fd=root_fd,
    )
    try:
        with os.fdopen(os.dup(manifest_fd), "wb") as handle:
            written = handle.write(manifest_bytes)
            handle.flush()
            os.fsync(handle.fileno())
        if written != len(manifest_bytes):
            raise SystemExit("visual evidence manifest write was incomplete")
        manifest_metadata = os.fstat(manifest_fd)
        if not stat.S_ISREG(manifest_metadata.st_mode) or manifest_metadata.st_size != len(manifest_bytes):
            raise SystemExit("visual evidence manifest descriptor does not match published bytes")
    finally:
        os.close(manifest_fd)
finally:
    os.close(root_fd)
PY

VISUAL_EVIDENCE_MANIFEST_SHA256="$(shasum -a 256 "$VISUAL_EVIDENCE_MANIFEST" | awk '{print $1}')"
if [[ ! "$VISUAL_EVIDENCE_MANIFEST_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Could not derive a valid SHA-256 digest for the Simulator visual evidence manifest." >&2
  exit 23
fi
printf '%s\n' \
  "capture_simulator_visual_evidence_manifest=$VISUAL_EVIDENCE_MANIFEST" \
  "capture_simulator_visual_evidence_manifest_sha256=$VISUAL_EVIDENCE_MANIFEST_SHA256" \
  >> "$ARTIFACTS_DIR/environment.txt"
