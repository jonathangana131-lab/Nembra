import Foundation

/// Redacts credential-shaped values from structured Tuya application updates before callers
/// project them into strings or retain them as Capture evidence.
///
/// This type classifies only secret custody. It does not decode DP semantics, infer telemetry,
/// or create any query/write/control authority.
public enum TuyaApplicationUpdateSecretSanitizer {
    public static let redactedValue = "<redacted>"

    private static let secretKeyFragments = [
        "localkey",
        "accesstoken",
        "refreshtoken",
        "seckey",
        "authkey",
    ]

    /// Returns a string-projected update whose credential-shaped values have already been
    /// recursively replaced. Non-secret values remain application evidence exactly as values,
    /// but the resulting strings are not raw BLE bytes or decoded DP semantics.
    public static func sanitize(_ update: [AnyHashable: Any]) -> [String: String] {
        var output: [String: String] = [:]
        output.reserveCapacity(update.count)

        for (rawKey, rawValue) in update {
            let key = String(describing: rawKey)
            let sanitized = sanitizeValue(rawValue, underKey: key)
            output[key] = String(describing: sanitized)
        }
        return output
    }

    private static func sanitizeValue(_ value: Any, underKey key: String?) -> Any {
        if let key, isSecretKey(key) {
            return redactedValue
        }

        if let dictionary = value as? [AnyHashable: Any] {
            var output: [String: Any] = [:]
            output.reserveCapacity(dictionary.count)
            for (rawNestedKey, nestedValue) in dictionary {
                let nestedKey = String(describing: rawNestedKey)
                output[nestedKey] = sanitizeValue(nestedValue, underKey: nestedKey)
            }
            return output
        }

        if let array = value as? [Any] {
            return array.map { sanitizeValue($0, underKey: nil) }
        }

        return value
    }

    private static func isSecretKey(_ key: String) -> Bool {
        let normalized = key
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return secretKeyFragments.contains(where: normalized.contains)
    }
}
