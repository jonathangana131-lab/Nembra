import Foundation

/// Pure custody policy for authenticated Tuya application evidence before it enters
/// Nembra-owned immutable event metadata.
///
/// The SDK payload remains opaque application evidence. It must not be able to
/// impersonate Nembra-owned provenance fields, and the exact Tuya account UID used
/// as source authority must not cross into an exported Capture event.
///
/// This primitive does not assign DP meaning, authenticate a device, create a
/// connection generation, or promote application values into telemetry authority.
public enum TuyaAuthenticatedApplicationEventCustody {
    public static let trustedGenerationKey = "generation"
    public static let accountUIDRedactionMarker = "<redacted-account-uid>"

    /// Preserves every admitted application field while reserving `generation` for
    /// Nembra's trusted connection-token provenance.
    ///
    /// A colliding SDK field is retained under a deterministic `application.` namespace.
    /// Further collisions are resolved by repeatedly prefixing `application.` so no
    /// opaque application value is silently discarded. Keys are processed in sorted
    /// order to make that collision policy stable across dictionary iteration order.
    ///
    /// The exact leased account UID is redacted from both application keys and values.
    /// A generic key such as `uid` is intentionally retained when it does not contain
    /// that leased account identifier.
    public static func eventDetails(
        applicationUpdate: [String: String],
        trustedGeneration: String,
        accountUID: String?
    ) -> [String: String] {
        let normalizedAccountUID = normalizedUID(accountUID)
        var output: [String: String] = [:]
        var occupiedKeys: Set<String> = [trustedGenerationKey]

        for key in applicationUpdate.keys.sorted() {
            guard let value = applicationUpdate[key] else { continue }

            let sanitizedKey = redactAccountUID(in: key, accountUID: normalizedAccountUID)
            let sanitizedValue = redactAccountUID(in: value, accountUID: normalizedAccountUID)

            var admittedKey = key == trustedGenerationKey
                ? "application.\(sanitizedKey)"
                : sanitizedKey

            while occupiedKeys.contains(admittedKey) {
                admittedKey = "application.\(admittedKey)"
            }

            occupiedKeys.insert(admittedKey)
            output[admittedKey] = sanitizedValue
        }

        output[trustedGenerationKey] = trustedGeneration
        return output
    }

    private static func normalizedUID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func redactAccountUID(in value: String, accountUID: String?) -> String {
        guard let accountUID else { return value }
        return value.replacingOccurrences(
            of: accountUID,
            with: accountUIDRedactionMarker,
            options: [.caseInsensitive, .literal]
        )
    }
}
