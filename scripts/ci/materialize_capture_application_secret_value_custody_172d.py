from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
P = ROOT / 'NembraApp/App/NembraCaptureEntrypoint.swift'
s = P.read_text(encoding='utf-8')

old_callback = '''        for (key, value) in dps {
            let keyString = String(describing: key)
            let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
            if Self.secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                sanitized[keyString] = "<redacted>"
            } else {
                sanitized[keyString] = String(describing: Self.redactApplicationSecrets(value))
            }
        }
'''
new_callback = '''        for (key, value) in dps {
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
        }
'''
if s.count(old_callback) != 1:
    raise SystemExit(f'callback target count {s.count(old_callback)}')
s = s.replace(old_callback, new_callback, 1)

marker = '''    private static func redactApplicationSecrets(_ object: Any) -> Any {
'''
helper = '''    private static var exactSecretValues: [String] {
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
if s.count(marker) != 1 or 'private static var exactSecretValues:' in s:
    raise SystemExit('sanitizer insertion seam changed or repair already present')
s = s.replace(marker, helper + marker, 1)

old_nested = '''            for (key, value) in dictionary {
                let keyString = String(describing: key)
                let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
                if secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                    sanitized[keyString] = "<redacted>"
                } else {
                    sanitized[keyString] = redactApplicationSecrets(value)
                }
            }
'''
new_nested = '''            for (key, value) in dictionary {
                let keyString = String(describing: key)
                let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
                let custodySafeKey = redactingExactApplicationSecrets(in: keyString)
                let retainedKey = collisionSafeRedactedKey(custodySafeKey, in: sanitized)
                if secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                    sanitized[retainedKey] = "<redacted>"
                } else {
                    sanitized[retainedKey] = redactApplicationSecrets(value)
                }
            }
'''
if s.count(old_nested) != 1:
    raise SystemExit(f'nested dictionary target count {s.count(old_nested)}')
s = s.replace(old_nested, new_nested, 1)

old_tail = '''        if let array = object as? [Any] {
            return array.map(redactApplicationSecrets)
        }
        return object
'''
new_tail = '''        if let array = object as? [Any] {
            return array.map(redactApplicationSecrets)
        }
        if let string = object as? String {
            return redactingExactApplicationSecrets(in: string)
        }
        return object
'''
if s.count(old_tail) != 1:
    raise SystemExit(f'scalar tail target count {s.count(old_tail)}')
s = s.replace(old_tail, new_tail, 1)

P.write_text(s, encoding='utf-8')

driver = s[s.index('@MainActor\nprivate final class SmartLifeDriver'):s.index('#endif\n\nprivate enum AppleAccountAuthorizationError')]
required = (
    'NembraTuyaPrivateIdentity.appKey', 'NembraTuyaPrivateIdentity.appSecret',
    'private static var exactSecretValues:', 'redactingExactApplicationSecrets',
    'collisionSafeRedactedKey', 'options: [.literal]',
    'sanitized[retainedKey] = "<redacted>"',
    'if let string = object as? String',
)
for token in required:
    if token not in driver:
        raise SystemExit(f'missing contract token: {token}')
if 'String(describing: Self.redactApplicationSecrets(value))' in driver:
    raise SystemExit('unsafe direct stringification still present')
for fragment in ('localkey','sessionkey','appkey','appsecret','password','accounttoken','accesstoken','refreshtoken','authkey','seckey'):
    if f'"{fragment}"' not in driver:
        raise SystemExit(f'credential key classifier lost: {fragment}')
