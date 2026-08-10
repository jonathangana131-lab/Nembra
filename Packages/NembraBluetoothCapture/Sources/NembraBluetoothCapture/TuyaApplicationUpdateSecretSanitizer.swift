import Foundation

/// Fail-closed secret custody for structured Tuya application updates.
///
/// This sanitizer deliberately does not interpret DP semantics. It only removes
/// values whose dictionary keys are credential-shaped before an SDK update can
/// be projected into diagnostic strings or accepted export events.
public enum TuyaApplicationUpdateSecretSanitizer: Sendable {
    public static let redactedValue = "<redacted>"

    private static let secretKeyFragments = [
        "localkey",
        "accesstoken",
        "refreshtoken",
        "authkey",
        "seckey",
    ]

    /// Produces the string projection consumed by Capture diagnostics only after
    /// recursively redacting credential-shaped values.
    public static func sanitize(_ update: [AnyHashable: Any]) -> [String: String] {
        var sanitized: [String: String] = [:]
        sanitized.reserveCapacity(update.count)

        for (key, value) in update {
            let keyString = String(describing: key)
            if isSecretKey(keyString) {
                sanitized[keyString] = redactedValue
            } else {
                sanitized[keyString] = String(describing: redactApplicationSecrets(value))
            }
        }

        return sanitized
    }

    private static func redactApplicationSecrets(_ object: Any) -> Any {
        if let dictionary = object as? [AnyHashable: Any] {
            var sanitized: [String: Any] = [:]
            sanitized.reserveCapacity(dictionary.count)

            for (key, value) in dictionary {
                let keyString = String(describing: key)
                sanitized[keyString] = isSecretKey(keyString)
                    ? redactedValue
                    : redactApplicationSecrets(value)
            }

            return sanitized
        }

        if let array = object as? [Any] {
            return array.map(redactApplicationSecrets)
        }

        return object
    }

    private static func isSecretKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
        return secretKeyFragments.contains { normalized.contains($0) }
    }
}
