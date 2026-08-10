from pathlib import Path

SOURCE = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = SOURCE.read_text()

old = '''        var redacted: [String: String] = [:]
        redacted.reserveCapacity(update.count)
        for (key, value) in update {
            let redactedKey = key.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            redacted[redactedKey] = value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
        }
        return redacted
'''

new = '''        var redacted: [String: String] = [:]
        redacted.reserveCapacity(update.count)
        for key in update.keys.sorted() {
            guard let value = update[key] else { continue }
            let redactedKey = key.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            let redactedValue = value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )

            // Account-UID redaction can collapse distinct malformed SDK keys onto one safe key.
            // Keep every accepted evidence value under deterministic non-sensitive suffixes.
            var admittedKey = redactedKey
            var collisionIndex = 2
            while redacted[admittedKey] != nil {
                admittedKey = "\\(redactedKey)#\\(collisionIndex)"
                collisionIndex += 1
            }
            redacted[admittedKey] = redactedValue
        }
        return redacted
'''

if text.count(old) != 1:
    raise SystemExit(f"redaction helper anchor drifted: {text.count(old)}")
text = text.replace(old, new, 1)
SOURCE.write_text(text)

updated = SOURCE.read_text()
start = updated.index("private func redactedApplicationEventDetails(")
end = updated.index("private func startWatchdog", start)
helper = updated[start:end]
assert "for key in update.keys.sorted()" in helper
assert "var admittedKey = redactedKey" in helper
assert "while redacted[admittedKey] != nil" in helper
assert "collisionIndex" in helper
assert "redacted[admittedKey] = redactedValue" in helper
assert "redacted[redactedKey] = value.replacingOccurrences" not in helper
assert "<redacted-account-uid>" in helper
print("materialized account-UID redaction key-collision preservation")
