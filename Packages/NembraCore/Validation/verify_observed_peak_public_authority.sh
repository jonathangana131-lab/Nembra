#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

compile_must_fail_for_access_control() {
  local name="$1"
  local expected_symbol="$2"
  local source="$3"
  local probe_dir="$TMP_DIR/$name"
  local output="$probe_dir/build.log"

  mkdir -p "$probe_dir/Sources/Probe"
  ln -s "$PACKAGE_ROOT" "$probe_dir/NembraCore"

  cat > "$probe_dir/Package.swift" <<'MANIFEST'
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ExternalObservedPeakAuthorityProbe",
    dependencies: [
        .package(path: "NembraCore")
    ],
    targets: [
        .executableTarget(
            name: "Probe",
            dependencies: [
                .product(name: "NembraCore", package: "nembracore")
            ]
        )
    ]
)
MANIFEST

  printf '%s\n' "$source" > "$probe_dir/Sources/Probe/main.swift"

  set +e
  swift build \
    --package-path "$probe_dir" \
    --scratch-path "$probe_dir/.build" \
    >"$output" 2>&1
  local status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    echo "ERROR: external probe '$name' unexpectedly compiled; durable observed-peak authority leaked into public API." >&2
    cat "$output" >&2
    exit 1
  fi

  if ! grep -Fq "$expected_symbol" "$output"; then
    echo "ERROR: external probe '$name' failed without naming protected symbol '$expected_symbol'; this does not prove the intended boundary." >&2
    cat "$output" >&2
    exit 1
  fi

  if ! grep -Eiq "inaccessible|internal|protection level|access level" "$output"; then
    echo "ERROR: external probe '$name' failed for a non-access-control reason; this does not prove the intended boundary." >&2
    cat "$output" >&2
    exit 1
  fi

  echo "PASS: external Swift package '$name' is denied access to '$expected_symbol'."
}

compile_must_fail_for_access_control \
  evidence_assessment \
  assessment \
  $'import NembraCore\n\nfunc attempt(_ evidence: RideObservedPeakHistoryEvidence) {\n    _ = try? evidence.assessment()\n}'

compile_must_fail_for_access_control \
  joined_assessment \
  assessment \
  $'import NembraCore\n\nfunc attempt(_ joined: RideHistoryObservedPeakJoinedRecord) {\n    _ = try? joined.assessment()\n}'

compile_must_fail_for_access_control \
  assessment_type \
  RideObservedPeakHistoryAssessment \
  $'import NembraCore\n\nfunc attempt() {\n    _ = RideObservedPeakHistoryAssessment.self\n}'

echo "Observed-peak durable eligibility remains module-owned; public Codable evidence is descriptive only."
