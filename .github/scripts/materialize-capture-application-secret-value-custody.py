from pathlib import Path

app = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = app.read_text(encoding="utf-8")

unsafe_callback = '''        for (key, value) in dps {
            let keyString = String(describing: key)
            let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
            if Self.secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                sanitized[keyString] = "<redacted>"
            } else {
                sanitized[keyString] = String(describing: Self.redactApplicationSecrets(value))
            }
        }'''
safe_callback = '''        for (key, value) in dps {
            let keyString = String(describing: key)
            let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
            let custodySafeKey = Self.redactingExactApplicationSecrets(in: keyString)
            let retainedKey = Self.collisionSafeRedactedKey(custodySafeKey, in: sanitized)
            if Self.secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                sanitized[retainedKey] = "<redacted>"
            } else {
                let recursivelySanitized = Self.redactApplicationSecrets(value)
                sanitized[retainedKey] = Self.redactingExactApplicationSecrets(
                    in: String(describing: recursivelySanitized)
                )
            }
        }'''
if source.count(unsafe_callback) != 1:
    raise SystemExit(f"expected one unsafe application callback seam, found {source.count(unsafe_callback)}")
source = source.replace(unsafe_callback, safe_callback, 1)

sanitizer_marker = '''    private static func redactApplicationSecrets(_ object: Any) -> Any {'''
secret_helpers = '''    private static var exactSecretValues: [String] {
#if canImport(NembraTuyaPrivateConfig)
        [
            NembraTuyaPrivateIdentity.appKey,
            NembraTuyaPrivateIdentity.appSecret,
        ].filter { !$0.isEmpty }
#else
        []
#endif
    }

    private static func redactingExactApplicationSecrets(in value: String) -> String {
        exactSecretValues.reduce(value) { partiallyRedacted, secret in
            partiallyRedacted.replacingOccurrences(
                of: secret,
                with: "<redacted>",
                options: [.literal]
            )
        }
    }

    private static func collisionSafeRedactedKey<Value>(
        _ key: String,
        in dictionary: [String: Value]
    ) -> String {
        guard dictionary[key] != nil else { return key }
        var suffix = 2
        while dictionary["\\(key)#\\(suffix)"] != nil {
            suffix += 1
        }
        return "\\(key)#\\(suffix)"
    }

'''
if source.count(sanitizer_marker) != 1:
    raise SystemExit("application sanitizer insertion seam did not match exactly once")
source = source.replace(sanitizer_marker, secret_helpers + sanitizer_marker, 1)

unsafe_nested = '''            for (key, value) in dictionary {
                let keyString = String(describing: key)
                let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
                if secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                    sanitized[keyString] = "<redacted>"
                } else {
                    sanitized[keyString] = redactApplicationSecrets(value)
                }
            }'''
safe_nested = '''            for (key, value) in dictionary {
                let keyString = String(describing: key)
                let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
                let custodySafeKey = redactingExactApplicationSecrets(in: keyString)
                let retainedKey = collisionSafeRedactedKey(custodySafeKey, in: sanitized)
                if secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                    sanitized[retainedKey] = "<redacted>"
                } else {
                    sanitized[retainedKey] = redactApplicationSecrets(value)
                }
            }'''
if source.count(unsafe_nested) != 1:
    raise SystemExit(f"expected one recursive dictionary sanitizer seam, found {source.count(unsafe_nested)}")
source = source.replace(unsafe_nested, safe_nested, 1)

leaf = '''        if let array = object as? [Any] {
            return array.map(redactApplicationSecrets)
        }
        return object'''
safe_leaf = '''        if let array = object as? [Any] {
            return array.map(redactApplicationSecrets)
        }
        if let string = object as? String {
            return redactingExactApplicationSecrets(in: string)
        }
        return object'''
if source.count(leaf) != 1:
    raise SystemExit("application sanitizer scalar leaf seam did not match exactly once")
source = source.replace(leaf, safe_leaf, 1)

app.write_text(source, encoding="utf-8")

final = app.read_text(encoding="utf-8")
start = final.index("@MainActor\nprivate final class SmartLifeDriver")
end = final.index("#endif\n\nprivate enum AppleAccountAuthorizationError", start)
driver = final[start:end]
callback_start = driver.index("func device(_ device: ThingSmartDevice?, dpsUpdate")
callback_end = driver.index("private static let secretKeyFragments", callback_start)
callback = driver[callback_start:callback_end]
assert "NembraTuyaPrivateIdentity.appKey" in driver
assert "NembraTuyaPrivateIdentity.appSecret" in driver
assert "exactSecretValues" in driver
assert "replacingOccurrences" in driver
assert "String(describing: Self.redactApplicationSecrets(value))" not in callback
assert "redactingExactApplicationSecrets" in callback
assert "collisionSafeRedactedKey" in callback
assert '"localkey"' in driver and '"sessionkey"' in driver and '"appkey"' in driver and '"appsecret"' in driver
print("application secret-value custody materializer contract: PASS")
