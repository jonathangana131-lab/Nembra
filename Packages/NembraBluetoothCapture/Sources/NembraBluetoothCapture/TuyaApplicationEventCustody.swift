import Foundation

/// Fail-closed custody for authenticated Tuya application evidence before it enters
/// Nembra's immutable event log. This helper preserves opaque application content while
/// keeping Nembra-owned provenance authoritative and removing the already-verified
/// account identifier from both application keys and values.
public enum TuyaApplicationEventCustody {
    public static let redactedAccountUIDMarker = "<redacted-account-uid>"

    /// Produces event details only when a non-empty application update and an exact
    /// verified account UID are both available. The returned `generation` field is
    /// always Nembra-owned provenance; an application field that could impersonate it
    /// is retained under a non-authoritative `application.generation` key instead.
    public static func admittedDetails(
        applicationUpdate: [String: String],
        verifiedAccountUID: String,
        connectionGeneration: UInt64
    ) -> [String: String]? {
        guard !applicationUpdate.isEmpty else { return nil }

        let accountUID = verifiedAccountUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountUID.isEmpty else { return nil }

        var admitted: [String: String] = [:]
        admitted.reserveCapacity(applicationUpdate.count + 1)

        for key in applicationUpdate.keys.sorted() {
            guard let value = applicationUpdate[key] else { continue }

            let scrubbedKey = redactExactAccountUID(in: key, accountUID: accountUID)
            let scrubbedValue = redactExactAccountUID(in: value, accountUID: accountUID)
            let custodyKey = applicationEvidenceKey(for: scrubbedKey)
            insertPreservingCollision(
                value: scrubbedValue,
                preferredKey: custodyKey,
                into: &admitted
            )
        }

        // Write trusted provenance last as a defense-in-depth guarantee. Application
        // evidence has already been namespaced away from this reserved field.
        admitted["generation"] = String(connectionGeneration)
        return admitted
    }

    private static func redactExactAccountUID(in value: String, accountUID: String) -> String {
        value.replacingOccurrences(
            of: accountUID,
            with: redactedAccountUIDMarker,
            options: [.literal]
        )
    }

    private static func applicationEvidenceKey(for key: String) -> String {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "generation" ? "application.generation" : key
    }

    private static func insertPreservingCollision(
        value: String,
        preferredKey: String,
        into details: inout [String: String]
    ) {
        guard details[preferredKey] != nil else {
            details[preferredKey] = value
            return
        }

        var suffix = 2
        while details["\(preferredKey)#\(suffix)"] != nil {
            suffix += 1
        }
        details["\(preferredKey)#\(suffix)"] = value
    }
}
