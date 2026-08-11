#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
LOCAL_SECRETS="$REPO_ROOT/LocalSecrets"
TARGET="$LOCAL_SECRETS/TuyaRuntime"
STAGING=""
BACKUP=""

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  local rc=$?
  if [[ -n "${STAGING:-}" && -d "$STAGING" ]]; then
    rm -rf "$STAGING" || true
  fi
  if [[ -n "${BACKUP:-}" && -d "$BACKUP" && ! -e "$TARGET" && ! -L "$TARGET" ]]; then
    mv "$BACKUP" "$TARGET" || true
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM HUP

[[ "$(uname -s)" == "Darwin" ]] || die "Run this private provisioning helper on the trusted field-build Mac."
[[ -x /usr/bin/python3 ]] || die "System Python 3 is required to write the local private identity pod safely."
[[ -t 0 ]] || die "Run this helper interactively in a terminal so AppSecret input can remain hidden."
cd "$REPO_ROOT"

git check-ignore -q -- LocalSecrets/ || die "LocalSecrets/ is not ignored by this accepted source. Refusing to write private Tuya identity material."
[[ ! -L "$LOCAL_SECRETS" ]] || die "LocalSecrets must not be a symbolic link."
mkdir -p "$LOCAL_SECRETS"
chmod 0700 "$LOCAL_SECRETS"
[[ -d "$LOCAL_SECRETS" && ! -L "$LOCAL_SECRETS" ]] || die "Could not establish a private local secrets directory."
[[ ! -L "$TARGET" ]] || die "Existing TuyaRuntime path is a symbolic link. Remove it manually before provisioning."

printf 'Tuya Developer Platform AppKey: '
IFS= read -r APP_KEY
printf 'Tuya Developer Platform AppSecret: '
IFS= read -r -s APP_SECRET
printf '\n'

[[ -n "$APP_KEY" ]] || die "AppKey cannot be empty."
[[ -n "$APP_SECRET" ]] || die "AppSecret cannot be empty."

STAGING="$(mktemp -d "$LOCAL_SECRETS/.TuyaRuntime.staging.XXXXXX")"
chmod 0700 "$STAGING"

# Secrets travel only through this process pipe, never argv or environment. The
# Python writer validates exact text, escapes Swift source safely, and creates a
# complete local pod under an owner-only staging directory before publication.
if ! printf '%s\n%s\n' "$APP_KEY" "$APP_SECRET" | /usr/bin/python3 -I -c '
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
raw = sys.stdin.buffer.read(4096)
parts = raw.split(b"\n")
if len(parts) != 3 or parts[-1] != b"":
    raise SystemExit("private identity input shape is invalid")
try:
    app_key = parts[0].decode("utf-8")
    app_secret = parts[1].decode("utf-8")
except UnicodeDecodeError as exc:
    raise SystemExit("private identity input must be valid UTF-8") from exc

def validate(value: str, label: str) -> None:
    encoded = value.encode("utf-8")
    if not value or len(encoded) > 1024:
        raise SystemExit(f"{label} has an invalid bounded size")
    if value != value.strip():
        raise SystemExit(f"{label} must not contain leading or trailing whitespace")
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in value):
        raise SystemExit(f"{label} contains a forbidden control character")

def swift_literal(value: str) -> str:
    out = []
    for ch in value:
        if ch == "\\":
            out.append("\\\\")
        elif ch == "\"":
            out.append("\\\"")
        else:
            out.append(ch)
    return "\"" + "".join(out) + "\""

validate(app_key, "AppKey")
validate(app_secret, "AppSecret")

sources = root / "Sources" / "NembraTuyaPrivateConfig"
sources.mkdir(parents=True, mode=0o700)
root.chmod(0o700)
(root / "Sources").chmod(0o700)
sources.chmod(0o700)

podspec = root / "NembraTuyaPrivateConfig.podspec"
podspec.write_text("""Pod::Spec.new do |s|\n  s.name = \"NembraTuyaPrivateConfig\"\n  s.version = \"1.0.0\"\n  s.summary = \"Local-only Tuya identity for Nembra Capture\"\n  s.description = \"Ignored private build input containing the Nembra Capture Tuya AppKey/AppSecret.\"\n  s.homepage = \"https://example.invalid/nembra-private-config\"\n  s.license = { :type => \"Private\", :text => \"Local build input; not for distribution\" }\n  s.author = { \"Nembra\" => \"local-only\" }\n  s.source = { :git => \"https://example.invalid/nembra-private-config.git\", :tag => s.version.to_s }\n  s.ios.deployment_target = \"17.0\"\n  s.swift_version = \"5.9\"\n  s.module_name = \"NembraTuyaPrivateConfig\"\n  s.source_files = \"Sources/NembraTuyaPrivateConfig/**/*.swift\"\nend\n""", encoding="utf-8")

swift = sources / "NembraTuyaPrivateIdentity.swift"
swift.write_text(
    "public enum NembraTuyaPrivateIdentity {\n"
    f"    public static let appKey = {swift_literal(app_key)}\n"
    f"    public static let appSecret = {swift_literal(app_secret)}\n"
    "}\n",
    encoding="utf-8",
)

for path in (podspec, swift):
    path.chmod(0o600)
    metadata = path.stat()
    if not stat.S_ISREG(metadata.st_mode) or (metadata.st_mode & 0o077):
        raise SystemExit("generated private identity file did not retain owner-only regular-file custody")
' "$STAGING"
then
  unset APP_KEY APP_SECRET || true
  die "Private Tuya identity generation failed. No existing field identity was replaced."
fi
unset APP_KEY APP_SECRET || true

[[ -f "$STAGING/NembraTuyaPrivateConfig.podspec" ]] || die "Generated private podspec is missing."
[[ -f "$STAGING/Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift" ]] || die "Generated private Swift identity is missing."

if [[ -e "$TARGET" ]]; then
  [[ -d "$TARGET" && ! -L "$TARGET" ]] || die "Existing TuyaRuntime is not a normal directory. Remove it manually before provisioning."
  BACKUP="$LOCAL_SECRETS/.TuyaRuntime.previous.$$"
  [[ ! -e "$BACKUP" && ! -L "$BACKUP" ]] || die "Private identity backup path already exists; refusing replacement."
  mv "$TARGET" "$BACKUP"
fi

if ! mv "$STAGING" "$TARGET"; then
  die "Could not publish the complete private Tuya identity pod. The previous identity will be restored when possible."
fi
STAGING=""
if [[ -n "$BACKUP" && -d "$BACKUP" ]]; then
  rm -rf "$BACKUP"
fi
BACKUP=""

say "Private Tuya identity pod provisioned"
printf '%s\n' "Location: $TARGET" \
  "Next: run Scripts/bootstrap_capture_tuya_sdk.sh from this exact accepted source." \
  "No AppKey/AppSecret value was printed, placed in argv/environment, or written outside ignored LocalSecrets/."
