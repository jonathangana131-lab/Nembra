import Foundation

/// Pure custody transform for authenticated Tuya application evidence before it can enter
/// Nembra's immutable event prefix.
///
/// This type does not interpret DP/application semantics. It only enforces two provenance/privacy
/// boundaries already earned elsewhere: the exact leased account UID must not be exported, and
/// Nembra-owned connection generation metadata must not be forgeable by application keys.
public enum TuyaApplicationEventCustody: Sendable {
    public static let accountUIDRedactionMarker = "<redacted-account-uid>"

    /// Returns event details safe for immutable event custody, or `nil` when the caller has not
    /// supplied the exact account/generation authority required to make the transformation.
    ///
    /// - Important: `leasedAccountUID` is expected to come from the already-earned same-account
    ///   membership lease. This helper never queries account state and cannot promote authority.
    public static func acceptedEventDetails(
        applicationUpdate: [String: String],
        leasedAccountUID: String,
        trustedGeneration: String
    ) -> [String: String]? {
        let accountUID = leasedAccountUID.trimmingCharacters(in: .whitespacesAndNewlines)
        let generation = trustedGeneration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountUID.isEmpty, !generation.isEmpty else { return nil }

        // If the independently trusted provenance value itself contains the exact account identity,
        // there is no truthful way to both preserve that value and honor the no-account-UID export
        // promise. Fail closed rather than silently weakening either contract.
        guard !generation.contains(accountUID) else { return nil }

        var details: [String: String] = [:]
        var occupiedKeys: Set<String> = ["generation"]

        // Dictionary order is not evidence. Sorting only makes malformed-key collision handling
        // deterministic and testable; it does not create chronology or application semantics.
        for rawKey in applicationUpdate.keys.sorted() {
            guard let rawValue = applicationUpdate[rawKey] else { continue }
            let redactedKey = redactAccountUID(in: rawKey, accountUID: accountUID)
            let redactedValue = redactAccountUID(in: rawValue, accountUID: accountUID)

            // Application content may use Nembra-reserved metadata names. Preserve the opaque
            // content under an application namespace rather than allowing it to impersonate
            // Nembra authority or dropping it silently.
            let baseKey = redactedKey == "generation"
                ? "application.generation"
                : redactedKey
            let custodyKey = uniqueKey(baseKey, occupiedKeys: &occupiedKeys)
            details[custodyKey] = redactedValue
        }

        details["generation"] = generation

        // Defense in depth for future edits to the transform: no exact leased account identifier
        // may survive in either dictionary dimension once custody is admitted.
        guard details.keys.allSatisfy({ !$0.contains(accountUID) }),
              details.values.allSatisfy({ !$0.contains(accountUID) }) else {
            return nil
        }
        return details
    }

    private static func redactAccountUID(in value: String, accountUID: String) -> String {
        value.replacingOccurrences(of: accountUID, with: accountUIDRedactionMarker)
    }

    private static func uniqueKey(
        _ proposedKey: String,
        occupiedKeys: inout Set<String>
    ) -> String {
        if occupiedKeys.insert(proposedKey).inserted {
            return proposedKey
        }

        var suffix = 2
        while true {
            let candidate = "\(proposedKey)#\(suffix)"
            if occupiedKeys.insert(candidate).inserted {
                return candidate
            }
            suffix += 1
        }
    }
}
