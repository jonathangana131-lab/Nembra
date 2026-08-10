from pathlib import Path
import sys

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationSecretValueCustodySourceTests.swift")


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return source.replace(old, new, 1)


def apply() -> None:
    source = APP.read_text(encoding="utf-8")
    old_callback = '''        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            let keyString = String(describing: key)
            let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
            if Self.secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                sanitized[keyString] = "<redacted>"
            } else {
                sanitized[keyString] = String(describing: Self.redactApplicationSecrets(value))
            }
        }
        onApplicationUpdate?(sanitized)
'''
    new_callback = '''        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            let keyString = String(describing: key)
            let exportSafeKey = Self.redactKnownSecretValues(in: keyString)
            let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
            if Self.secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                sanitized[exportSafeKey] = "<redacted>"
            } else {
                let sanitizedValue = Self.redactApplicationSecrets(value)
                sanitized[exportSafeKey] = Self.redactKnownSecretValues(in: String(describing: sanitizedValue))
            }
        }
        onApplicationUpdate?(sanitized)
'''
    source = replace_once(source, old_callback, new_callback, "application callback boundary")

    marker = '''    private static func redactApplicationSecrets(_ object: Any) -> Any {
'''
    helpers = '''    private static var exactSecretValues: [String] {
#if canImport(NembraTuyaPrivateConfig)
        [NembraTuyaPrivateIdentity.appKey, NembraTuyaPrivateIdentity.appSecret]
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
#else
        []
#endif
    }

    private static func redactKnownSecretValues(in value: String) -> String {
        exactSecretValues.reduce(value) { partial, secret in
            partial.replacingOccurrences(of: secret, with: "<redacted>", options: [.literal])
        }
    }

'''
    if source.count(marker) != 1:
        raise SystemExit("redactor marker changed")
    source = source.replace(marker, helpers + marker, 1)

    old_tail = '''        if let array = object as? [Any] {
            return array.map(redactApplicationSecrets)
        }
        return object
'''
    new_tail = '''        if let array = object as? [Any] {
            return array.map(redactApplicationSecrets)
        }
        if let string = object as? String {
            return redactKnownSecretValues(in: string)
        }
        return object
'''
    source = replace_once(source, old_tail, new_tail, "recursive scalar redaction")
    APP.write_text(source, encoding="utf-8")


def verify() -> None:
    source = APP.read_text(encoding="utf-8")
    a = source.index("@MainActor\nprivate final class SmartLifeDriver")
    b = source.index("#endif\n\nprivate enum AppleAccountAuthorizationError", a)
    driver = source[a:b]
    c = driver.index("func device(_ device: ThingSmartDevice?, dpsUpdate")
    d = driver.index("private static let secretKeyFragments", c)
    callback = driver[c:d]
    for needle in (
        "NembraTuyaPrivateIdentity.appKey",
        "NembraTuyaPrivateIdentity.appSecret",
        "private static var exactSecretValues",
        "private static func redactKnownSecretValues",
        "return array.map(redactApplicationSecrets)",
        "return redactKnownSecretValues(in: string)",
    ):
        if needle not in driver:
            raise SystemExit(f"missing secret-custody invariant: {needle}")
    for needle in (
        "redactKnownSecretValues(in: keyString)",
        "redactKnownSecretValues(in: String(describing: sanitizedValue))",
    ):
        if needle not in callback:
            raise SystemExit(f"callback boundary missing: {needle}")
    if "String(describing: Self.redactApplicationSecrets(value))" in callback:
        raise SystemExit("unsafe direct stringification remains")
    if not TEST.exists():
        raise SystemExit("regression missing")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "verify"
    if mode == "apply":
        apply()
    elif mode == "verify":
        verify()
    else:
        raise SystemExit(mode)
