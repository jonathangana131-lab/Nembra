from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationUpdateSecretRedactionSourceTests.swift"

OLD = '''    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            sanitized[String(describing: key)] = String(describing: value)
        }
        onApplicationUpdate?(sanitized)
    }
'''

NEW = '''    private static let applicationSecretKeyFragments = ["localkey", "accesstoken", "refreshtoken", "seckey", "authkey"]

    private static func normalizedApplicationKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func redactApplicationSecrets(_ object: Any) -> Any {
        if let dictionary = object as? [String: Any] {
            var output: [String: Any] = [:]
            for (key, value) in dictionary {
                let normalized = normalizedApplicationKey(key)
                if applicationSecretKeyFragments.contains(where: normalized.contains) {
                    output[key] = "<redacted>"
                } else {
                    output[key] = redactApplicationSecrets(value)
                }
            }
            return output
        }
        if let dictionary = object as? [AnyHashable: Any] {
            var output: [String: Any] = [:]
            for (key, value) in dictionary {
                let keyString = String(describing: key)
                let normalized = normalizedApplicationKey(keyString)
                if applicationSecretKeyFragments.contains(where: normalized.contains) {
                    output[keyString] = "<redacted>"
                } else {
                    output[keyString] = redactApplicationSecrets(value)
                }
            }
            return output
        }
        if let array = object as? [Any] {
            return array.map(redactApplicationSecrets)
        }
        return object
    }

    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            let keyString = String(describing: key)
            let normalized = Self.normalizedApplicationKey(keyString)
            if Self.applicationSecretKeyFragments.contains(where: normalized.contains) {
                sanitized[keyString] = "<redacted>"
            } else {
                sanitized[keyString] = String(describing: Self.redactApplicationSecrets(value))
            }
        }
        onApplicationUpdate?(sanitized)
    }
'''


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if "private static func redactApplicationSecrets(_ object: Any) -> Any" in source:
        raise SystemExit("application secret redaction already exists; re-inspect current product")
    if source.count(OLD) != 1:
        raise SystemExit(f"SmartLife dpsUpdate boundary changed: expected one raw block, found {source.count(OLD)}")
    ENTRYPOINT.write_text(source.replace(OLD, NEW, 1), encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    start = source.index("@MainActor\nprivate final class SmartLifeDriver")
    end = source.index("#endif\n\nprivate enum AppleAccountAuthorizationError", start)
    body = source[start:end]
    required = (
        'private static let applicationSecretKeyFragments = ["localkey", "accesstoken", "refreshtoken", "seckey", "authkey"]',
        "private static func redactApplicationSecrets(_ object: Any) -> Any",
        "key.lowercased().filter { $0.isLetter || $0.isNumber }",
        "array.map(redactApplicationSecrets)",
        "Self.normalizedApplicationKey(keyString)",
        'sanitized[keyString] = "<redacted>"',
        "String(describing: Self.redactApplicationSecrets(value))",
        "onApplicationUpdate?(sanitized)",
    )
    for token in required:
        if token not in body:
            raise SystemExit(f"application secret redaction token missing: {token}")
    if "sanitized[String(describing: key)] = String(describing: value)" in body:
        raise SystemExit("raw dpsUpdate string projection still bypasses redaction")
    for forbidden in ("publishDps", "writeValue", "connectBLE(", "disconnect"):
        if forbidden in body:
            raise SystemExit(f"secret custody introduced forbidden protocol/control authority: {forbidden}")
    if not TEST.exists():
        raise SystemExit("application secret-redaction source regression is missing")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
