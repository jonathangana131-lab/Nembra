import Foundation

/// Fail-closed credential custody for structured Tuya application updates.
///
/// This sanitizer owns no protocol semantics. It only prevents credential-shaped
/// values from crossing into string-projected event/export custody.
public enum TuyaApplicationUpdateSecretSanitizer: Sendable {
    public static let redactedValue = "<redacted>"
    public static let redactedAccountUIDValue = "<redacted-account-uid>"

    public static let secretKeyFragments = [
        "localkey",
        "sessionkey",
        "appkey",
        "appsecret",
        "password",
        "accounttoken",
        "accesstoken",
        "refreshtoken",
        "authkey",
        "seckey",
    ]

    public static func normalizedKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func isSecretKey(_ key: String) -> Bool {
        let normalized = normalizedKey(key)
        return secretKeyFragments.contains(where: { normalized.contains($0) })
    }

    public static func sanitize(_ object: Any) -> Any {
        if let dictionary = object as? [AnyHashable: Any] {
            var sanitized: [String: Any] = [:]
            sanitized.reserveCapacity(dictionary.count)
            for (key, value) in dictionary {
                let keyString = String(describing: key)
                sanitized[keyString] = isSecretKey(keyString)
                    ? redactedValue
                    : sanitize(value)
            }
            return sanitized
        }
        if let array = object as? [Any] {
            return array.map(sanitize)
        }
        return object
    }

    public static func sanitizeForStringProjection(
        _ updates: [AnyHashable: Any]
    ) -> [String: String] {
        var sanitized: [String: String] = [:]
        sanitized.reserveCapacity(updates.count)
        for (key, value) in updates {
            let keyString = String(describing: key)
            sanitized[keyString] = isSecretKey(keyString)
                ? redactedValue
                : String(describing: sanitize(value))
        }
        return sanitized
    }

    /// Removes one exact, already-authorized sensitive value from projected application evidence.
    /// Generic `uid` keys are deliberately not treated as account identity. Exact occurrences are
    /// removed from both keys and values so accepted export custody cannot retain the sensitive value
    /// merely because the SDK supplied it as a field name.
    public static func redactingExactSensitiveValue(
        in updates: [String: String],
        sensitiveValue: String,
        replacement: String
    ) -> [String: String] {
        guard !sensitiveValue.isEmpty else { return updates }
        var redacted: [String: String] = [:]
        redacted.reserveCapacity(updates.count)
        for (key, value) in updates {
            let safeKey = key.replacingOccurrences(
                of: sensitiveValue,
                with: replacement,
                options: [.literal]
            )
            let safeValue = value.replacingOccurrences(
                of: sensitiveValue,
                with: replacement,
                options: [.literal]
            )
            redacted[safeKey] = safeValue
        }
        return redacted
    }

    public static func redactingAccountUID(
        in updates: [String: String],
        verifiedAccountUID: String
    ) -> [String: String] {
        redactingExactSensitiveValue(
            in: updates,
            sensitiveValue: verifiedAccountUID,
            replacement: redactedAccountUIDValue
        )
    }
}
