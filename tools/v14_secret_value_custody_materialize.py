from pathlib import Path

p = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = p.read_text()

callback_old = '''        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            let keyString = String(describing: key)
            let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
            if Self.secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                sanitized[keyString] = "<redacted>"
            } else {
                sanitized[keyString] = String(describing: Self.redactApplicationSecrets(value))
            }
        }
'''
callback_new = '''        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            let keyString = String(describing: key)
            let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
            let redactedKey = Self.redactKnownPrivateSecrets(in: keyString)
            var custodyKey = redactedKey
            var collisionSuffix = 2
            while sanitized[custodyKey] != nil {
                custodyKey = "\\(redactedKey)#\\(collisionSuffix)"
                collisionSuffix += 1
            }
            if Self.secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                sanitized[custodyKey] = "<redacted>"
            } else {
                sanitized[custodyKey] = Self.redactedApplicationDescription(value)
            }
        }
'''
if s.count(callback_old) != 1:
    raise SystemExit(f"callback seam drifted: {s.count(callback_old)}")
s = s.replace(callback_old, callback_new, 1)

anchor = '''    private static func redactApplicationSecrets(_ object: Any) -> Any {
'''
if s.count(anchor) != 1:
    raise SystemExit(f"sanitizer seam drifted: {s.count(anchor)}")
helpers = '''    private static var exactSecretValues: [String] {
#if canImport(NembraTuyaPrivateConfig)
        [NembraTuyaPrivateIdentity.appKey, NembraTuyaPrivateIdentity.appSecret]
            .filter { !$0.isEmpty }
#else
        []
#endif
    }

    private static func redactKnownPrivateSecrets(in text: String) -> String {
        var redacted = text
        for secret in exactSecretValues {
            redacted = redacted.replacingOccurrences(
                of: secret,
                with: "<redacted>",
                options: [.literal]
            )
        }
        return redacted
    }

    private static func redactedApplicationDescription(_ object: Any) -> String {
        redactKnownPrivateSecrets(in: String(describing: redactApplicationSecrets(object)))
    }

'''
s = s.replace(anchor, helpers + anchor, 1)

old_body = '''    private static func redactApplicationSecrets(_ object: Any) -> Any {
        if let dictionary = object as? [AnyHashable: Any] {
            var sanitized: [String: Any] = [:]
            for (key, value) in dictionary {
                let keyString = String(describing: key)
                let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
                if secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                    sanitized[keyString] = "<redacted>"
                } else {
                    sanitized[keyString] = redactApplicationSecrets(value)
                }
            }
            return sanitized
        }
        if let array = object as? [Any] {
            return array.map(redactApplicationSecrets)
        }
        return object
    }
'''
new_body = '''    private static func redactApplicationSecrets(_ object: Any) -> Any {
        if let dictionary = object as? [AnyHashable: Any] {
            var sanitized: [String: Any] = [:]
            for (key, value) in dictionary {
                let keyString = String(describing: key)
                let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
                let redactedKey = redactKnownPrivateSecrets(in: keyString)
                var custodyKey = redactedKey
                var collisionSuffix = 2
                while sanitized[custodyKey] != nil {
                    custodyKey = "\\(redactedKey)#\\(collisionSuffix)"
                    collisionSuffix += 1
                }
                if secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                    sanitized[custodyKey] = "<redacted>"
                } else {
                    sanitized[custodyKey] = redactApplicationSecrets(value)
                }
            }
            return sanitized
        }
        if let array = object as? [Any] {
            return array.map(redactApplicationSecrets)
        }
        let description = String(describing: object)
        let redactedDescription = redactKnownPrivateSecrets(in: description)
        return redactedDescription == description ? object : redactedDescription
    }
'''
if s.count(old_body) != 1:
    raise SystemExit("recursive sanitizer body drifted")
s = s.replace(old_body, new_body, 1)
p.write_text(s)

driver = s.split("@MainActor\nprivate final class SmartLifeDriver", 1)[1].split("#endif\n\nprivate enum AppleAccountAuthorizationError", 1)[0]
for token in [
    "NembraTuyaPrivateIdentity.appKey",
    "NembraTuyaPrivateIdentity.appSecret",
    "private static var exactSecretValues",
    "redactKnownPrivateSecrets(in: keyString)",
    "redactedApplicationDescription(value)",
    "while sanitized[custodyKey] != nil",
]:
    if token not in driver:
        raise SystemExit(f"missing source contract token: {token}")
if "String(describing: Self.redactApplicationSecrets(value))" in driver:
    raise SystemExit("unsafe direct key-only stringification remains")
