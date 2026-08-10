from pathlib import Path

PATH = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = PATH.read_text()

old_callback = "\n".join([
    "        for (key, value) in dps {",
    "            let keyString = String(describing: key)",
    "            let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }",
    "            if Self.secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {",
    "                sanitized[keyString] = \"<redacted>\"",
    "            } else {",
    "                sanitized[keyString] = String(describing: Self.redactApplicationSecrets(value))",
    "            }",
    "        }",
])
new_callback = "\n".join([
    "        for (key, value) in dps {",
    "            let keyString = String(describing: key)",
    "            let custodyKey = Self.redactExactSecretValues(in: keyString)",
    "            let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }",
    "            if Self.secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {",
    "                if custodyKey == keyString {",
    "                    sanitized[keyString] = \"<redacted>\"",
    "                } else {",
    "                    sanitized[custodyKey] = \"<redacted>\"",
    "                }",
    "            } else {",
    "                sanitized[custodyKey] = Self.redactedApplicationDescription(value)",
    "            }",
    "        }",
])
if source.count(old_callback) != 1:
    raise SystemExit(f"expected one current DPS callback shape, found {source.count(old_callback)}")
source = source.replace(old_callback, new_callback)

fragment_tail = "\n".join([
    '        "authkey",',
    '        "seckey",',
    "    ]",
    "",
    "    private static func redactApplicationSecrets(_ object: Any) -> Any {",
])
helper_tail = "\n".join([
    '        "authkey",',
    '        "seckey",',
    "    ]",
    "",
    "    private static var exactSecretValues: [String] {",
    "#if canImport(NembraTuyaPrivateConfig)",
    "        return [NembraTuyaPrivateIdentity.appKey, NembraTuyaPrivateIdentity.appSecret]",
    "            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }",
    "            .filter { !$0.isEmpty }",
    "#else",
    "        return []",
    "#endif",
    "    }",
    "",
    "    private static func redactExactSecretValues(in value: String) -> String {",
    "        exactSecretValues.reduce(value) { partial, secret in",
    "            partial.replacingOccurrences(of: secret, with: \"<redacted>\", options: [.literal])",
    "        }",
    "    }",
    "",
    "    private static func redactedApplicationDescription(_ object: Any) -> String {",
    "        String(describing: redactApplicationSecrets(object))",
    "    }",
    "",
    "    private static func redactApplicationSecrets(_ object: Any) -> Any {",
])
if source.count(fragment_tail) != 1:
    raise SystemExit(f"expected one secret classifier tail, found {source.count(fragment_tail)}")
source = source.replace(fragment_tail, helper_tail)

old_dictionary = "\n".join([
    "            for (key, value) in dictionary {",
    "                let keyString = String(describing: key)",
    "                let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }",
    "                if secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {",
    "                    sanitized[keyString] = \"<redacted>\"",
    "                } else {",
    "                    sanitized[keyString] = redactApplicationSecrets(value)",
    "                }",
    "            }",
])
new_dictionary = "\n".join([
    "            for (key, value) in dictionary {",
    "                let keyString = String(describing: key)",
    "                let custodyKey = redactExactSecretValues(in: keyString)",
    "                let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }",
    "                if secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {",
    "                    sanitized[custodyKey] = \"<redacted>\"",
    "                } else {",
    "                    sanitized[custodyKey] = redactApplicationSecrets(value)",
    "                }",
    "            }",
])
if source.count(old_dictionary) != 1:
    raise SystemExit(f"expected one recursive dictionary sanitizer, found {source.count(old_dictionary)}")
source = source.replace(old_dictionary, new_dictionary)

old_scalar = "\n".join([
    "        if let array = object as? [Any] {",
    "            return array.map(redactApplicationSecrets)",
    "        }",
    "        return object",
])
new_scalar = "\n".join([
    "        if let array = object as? [Any] {",
    "            return array.map(redactApplicationSecrets)",
    "        }",
    "        if let string = object as? String {",
    "            return redactExactSecretValues(in: string)",
    "        }",
    "        let rendered = String(describing: object)",
    "        let redacted = redactExactSecretValues(in: rendered)",
    "        return redacted == rendered ? object : redacted",
])
if source.count(old_scalar) != 1:
    raise SystemExit(f"expected one recursive scalar tail, found {source.count(old_scalar)}")
source = source.replace(old_scalar, new_scalar)

PATH.write_text(source)
