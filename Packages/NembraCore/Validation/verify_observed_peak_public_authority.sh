#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

compile_must_fail_for_boundary() {
  local name="$1"
  local expected_symbol="$2"
  local expected_diagnostic_regex="$3"
  local source="$4"
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
    echo "ERROR: external probe '$name' failed without naming protected symbol '$expected_symbol'; dependency/toolchain failure cannot prove the intended boundary." >&2
    cat "$output" >&2
    exit 1
  fi

  # Normal Swift module consumption may either diagnose a non-public declaration
  # explicitly as inaccessible/internal OR hide it from the imported public API and
  # report "has no member" / "cannot find ... in scope". Both are legitimate
  # boundary proofs when the diagnostic also names the exact protected symbol.
  if ! grep -Eiq "$expected_diagnostic_regex" "$output"; then
    echo "ERROR: external probe '$name' failed for an unexpected reason; this does not prove the intended boundary." >&2
    cat "$output" >&2
    exit 1
  fi

  echo "PASS: external Swift package '$name' cannot access '$expected_symbol'."
}

compile_must_fail_for_boundary \
  evidence_assessment \
  assessment \
  "inaccessible|internal|protection level|access level|has no member" \
  $'import NembraCore\n\nfunc attempt(_ evidence: RideObservedPeakHistoryEvidence) {\n    _ = try? evidence.assessment()\n}'

compile_must_fail_for_boundary \
  joined_assessment \
  assessment \
  "inaccessible|internal|protection level|access level|has no member" \
  $'import NembraCore\n\nfunc attempt(_ joined: RideHistoryObservedPeakJoinedRecord) {\n    _ = try? joined.assessment()\n}'

compile_must_fail_for_boundary \
  assessment_type \
  RideObservedPeakHistoryAssessment \
  "inaccessible|internal|protection level|access level|cannot find.*in scope|not in scope" \
  $'import NembraCore\n\nfunc attempt() {\n    _ = RideObservedPeakHistoryAssessment.self\n}'

echo "Observed-peak durable eligibility remains module-owned; public Codable evidence is descriptive only."
