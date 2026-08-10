#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
BASE_INSTALLER="$ROOT/scripts/field/install_one_time_capture.command"
PROCEDURE_ID="ES80-AUTHENTICATED-STATIONARY-v1"

[[ "$(uname -s)" == "Darwin" ]] || { printf 'ERROR: Run this on the Mac with Xcode and the intended iPhone connected.\n' >&2; exit 1; }
[[ -x "$BASE_INSTALLER" ]] || { printf 'ERROR: Canonical Capture field installer is missing or not executable.\n' >&2; exit 1; }
[[ -x /usr/bin/plutil ]] || { printf 'ERROR: System plutil is required for built-procedure verification.\n' >&2; exit 1; }
REAL_XCODEBUILD="$(command -v xcodebuild || true)"
[[ -n "$REAL_XCODEBUILD" && -x "$REAL_XCODEBUILD" ]] || { printf 'ERROR: xcodebuild is unavailable.\n' >&2; exit 1; }

SHIM_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nembra-capture-procedure-xcodebuild.XXXXXX")"
cleanup() { rm -rf -- "$SHIM_DIR"; }
trap cleanup EXIT

cat > "$SHIM_DIR/xcodebuild" <<'SHIM'
#!/bin/bash
set -euo pipefail

: "${NEMBRA_REAL_XCODEBUILD:?missing real xcodebuild path}"
: "${NEMBRA_CAPTURE_PROCEDURE_ID:?missing canonical Capture procedure}"

is_build=false
derived=""
previous=""
for argument in "$@"; do
    if [[ "$previous" == "-derivedDataPath" ]]; then
        derived="$argument"
    fi
    [[ "$argument" == "build" ]] && is_build=true
    previous="$argument"
done

if [[ "$is_build" != true ]]; then
    exec "$NEMBRA_REAL_XCODEBUILD" "$@"
fi

"$NEMBRA_REAL_XCODEBUILD" "$@" \
    "INFOPLIST_KEY_NembraCaptureProcedureIdentifier=$NEMBRA_CAPTURE_PROCEDURE_ID"

[[ -n "$derived" ]] || {
    printf 'ERROR: Capture build completed without a derived-data path; procedure read-back cannot be proven before install.\n' >&2
    exit 42
}

plist="$derived/Build/Products/Debug-iphoneos/Nembra Capture.app/Info.plist"
[[ -f "$plist" ]] || {
    printf 'ERROR: Capture build completed but the built Info.plist is unavailable for procedure read-back.\n' >&2
    exit 42
}

built_procedure="$(/usr/bin/plutil -extract NembraCaptureProcedureIdentifier raw -o - "$plist" 2>/dev/null || true)"
[[ "$built_procedure" == "$NEMBRA_CAPTURE_PROCEDURE_ID" ]] || {
    printf 'ERROR: Built Capture procedure does not match the canonical stationary procedure. Installation is blocked.\n' >&2
    exit 42
}

printf 'Built Capture procedure verified before installation: %s\n' "$NEMBRA_CAPTURE_PROCEDURE_ID"
SHIM
chmod 700 "$SHIM_DIR/xcodebuild"

export NEMBRA_REAL_XCODEBUILD="$REAL_XCODEBUILD"
export NEMBRA_CAPTURE_PROCEDURE_ID="$PROCEDURE_ID"
export PATH="$SHIM_DIR:$PATH"

"$BASE_INSTALLER" "$@"
