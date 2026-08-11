#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# The field path is fixed by default. A caller may override only the destination
# directory so CI can exercise this generator with dummy credentials without
# touching a developer's real ignored LocalSecrets/TuyaRuntime contents.
DEST="${NEMBRA_TUYA_RUNTIME_DIR:-$ROOT/LocalSecrets/TuyaRuntime}"
SOURCE_DIR="$DEST/Sources/NembraTuyaPrivateConfig"

umask 077
mkdir -p "$SOURCE_DIR"
chmod 700 "$DEST" "$DEST/Sources" "$SOURCE_DIR" 2>/dev/null || true

read -r -s -p "Tuya SmartLife SDK AppKey (input hidden): " APP_KEY
printf '\n'
read -r -s -p "Tuya SmartLife SDK AppSecret (input hidden): " APP_SECRET
printf '\n'

[[ -n "$APP_KEY" ]] || { echo "ERROR: AppKey is empty." >&2; exit 2; }
[[ -n "$APP_SECRET" ]] || { echo "ERROR: AppSecret is empty." >&2; exit 3; }

APP_KEY_B64="$(printf '%s' "$APP_KEY" | base64 | tr -d '\r\n')"
APP_SECRET_B64="$(printf '%s' "$APP_SECRET" | base64 | tr -d '\r\n')"
unset APP_KEY APP_SECRET

cat > "$DEST/NembraTuyaPrivateConfig.podspec" <<'RUBY'
Pod::Spec.new do |s|
  s.name = 'NembraTuyaPrivateConfig'
  s.version = '1.0.0'
  s.summary = 'Local-only Nembra Capture Tuya app identity.'
  s.description = 'Generated private field-build configuration. Never commit this pod.'
  s.homepage = 'https://localhost.invalid/nembra-private-config'
  s.license = { :type => 'Private' }
  s.author = { 'Nembra' => 'local-only' }
  s.source = { :git => 'https://localhost.invalid/nembra-private-config.git', :tag => s.version.to_s }
  s.platform = :ios, '17.0'
  s.swift_version = '6.0'
  s.source_files = 'Sources/NembraTuyaPrivateConfig/**/*.swift'
end
RUBY

cat > "$SOURCE_DIR/NembraTuyaPrivateIdentity.swift" <<SWIFT
import Foundation

public enum NembraTuyaPrivateIdentity {
    private static let encodedAppKey = "$APP_KEY_B64"
    private static let encodedAppSecret = "$APP_SECRET_B64"

    public static var appKey: String { decode(encodedAppKey) }
    public static var appSecret: String { decode(encodedAppSecret) }

    private static func decode(_ value: String) -> String {
        guard let data = Data(base64Encoded: value),
              let decoded = String(data: data, encoding: .utf8) else {
            preconditionFailure("Invalid local Tuya identity encoding")
        }
        return decoded
    }
}
SWIFT
unset APP_KEY_B64 APP_SECRET_B64
chmod 600 "$DEST/NembraTuyaPrivateConfig.podspec" "$SOURCE_DIR/NembraTuyaPrivateIdentity.swift"

cat <<EOF

Private Tuya app identity provisioned locally at:
  $DEST

Nothing was written to Git, shell history, host process argv, or stdout.
The generated source is compiled only by the SDK-integrated Capture workspace.
Next: run Scripts/bootstrap_capture_tuya_sdk.sh.
EOF
