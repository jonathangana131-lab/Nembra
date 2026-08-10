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

NEW = '''    private static let secretKeyFragments = ["localkey", "accesstoken", "refreshtoken", "seckey", "authkey"]

    private static func normalizedApplicationKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func redactApplicationSecrets(_ object: Any) -> Any {
        if let dictionary = object as? [String: Any] {
            var output: [String: Any] = [:]
            for (key, value) in dictionary {
                let normalized = normalizedApplicationKey(key)
                if secretKeyFragments.contains(where: normalized.contains) {
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
                if secretKeyFragments.contains(where: normalized.contains) {
                    output[keyString] = "<redacted>"
                } else {
                    output[keyString] = redactApplicationSecrets(value)
                }
            }
            return output
        }
        if let array = object as? [Any] { return array.map(redactApplicationSecrets) }
        return object
    }

    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            let keyString = String(describing: key)
            let normalized = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
            if Self.secretKeyFragments.contains(where: normalized.contains) {
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
    if source.count(OLD) != 1:
        raise SystemExit(f"SmartLife dpsUpdate boundary changed: expected one raw block, found {source.count(OLD)}")
    if NEW in source or "private static func redactApplicationSecrets(_ object: Any) -> Any" in source:
        raise SystemExit("application secret redaction is already present; re-inspect current product")
    ENTRYPOINT.write_text(source.replace(OLD, NEW, 1), encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if source.count(NEW) != 1:
        raise SystemExit(f"exact application secret-custody repair is not unique: {source.count(NEW)}")
    if OLD in source:
        raise SystemExit("raw dpsUpdate string projection still bypasses redaction")
    if not TEST.exists():
        raise SystemExit("application secret-redaction source regression is missing")

    test = TEST.read_text(encoding="utf-8")
    required_test_tokens = (
        "applicationUpdateCannotRetainCredentialShapedValues",
        "redactApplicationSecrets",
        "array.map(redactApplicationSecrets)",
        'sanitized[keyString] = \\"<redacted>\\"',
        "onApplicationUpdate?(sanitized)",
        "secretsRedacted: true",
        "tuya_application_update",
    )
    for token in required_test_tokens:
        if token not in test:
            raise SystemExit(f"application secret-redaction regression does not pin: {token}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
