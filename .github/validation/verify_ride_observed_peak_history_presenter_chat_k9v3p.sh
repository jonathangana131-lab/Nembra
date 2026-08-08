#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "$0")/../../Packages/NembraCore" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
PROBE_DIR="$TMP_DIR/probe"
mkdir -p "$PROBE_DIR/Sources/Probe"
ln -s "$PACKAGE_ROOT" "$PROBE_DIR/NembraCore"

cat > "$PROBE_DIR/Package.swift" <<'EOF'
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ExternalObservedPeakPresentationProbe",
    dependencies: [.package(path: "NembraCore")],
    targets: [
        .executableTarget(
            name: "Probe",
            dependencies: [.product(name: "NembraCore", package: "nembracore")]
        )
    ]
)
EOF

# Positive control: real external dependency resolution plus public projection visibility.
cat > "$PROBE_DIR/Sources/Probe/main.swift" <<'EOF'
import NembraCore

let state: RideHistoryObservedPeakPresentationState = .observedPeakUnavailable
print(state.rawValue)
EOF
swift build --package-path "$PROBE_DIR" --scratch-path "$PROBE_DIR/.build-positive"

# Negative control: external code must not be able to mint the projection from
# caller-authored durable joined evidence.
cat > "$PROBE_DIR/Sources/Probe/main.swift" <<'EOF'
import NembraCore

func attempt(_ joined: RideHistoryObservedPeakJoinedRecord) {
    _ = try? RideHistoryObservedPeakPresenter.present(joined)
}
EOF

set +e
swift build \
  --package-path "$PROBE_DIR" \
  --scratch-path "$PROBE_DIR/.build-negative" \
  >"$PROBE_DIR/negative.log" 2>&1
status=$?
set -e

if [[ $status -eq 0 ]]; then
    echo "ERROR: external package unexpectedly invoked RideHistoryObservedPeakPresenter." >&2
    exit 1
fi

if ! grep -Fq "RideHistoryObservedPeakPresenter" "$PROBE_DIR/negative.log"; then
    echo "ERROR: negative probe did not name the protected presenter." >&2
    cat "$PROBE_DIR/negative.log" >&2
    exit 1
fi

if ! grep -Eiq "inaccessible|internal|protection level|access level|cannot find.*in scope|not in scope" "$PROBE_DIR/negative.log"; then
    echo "ERROR: negative probe failed for an unrelated reason." >&2
    cat "$PROBE_DIR/negative.log" >&2
    exit 1
fi

echo "PASS: external package can consume public presentation state but cannot mint a presentation."