import Foundation
import Testing
@testable import NembraBluetoothCapture

extension TuyaApplicationReceiptChronologyTests {
    @Test("application delivery occurrence and chronology are sealed as one package-owned event")
    func shippingMutationDoesNotPairReceiptWithCallerSelectedPayloadPresence() throws {
        let ledgerSource = try readReceiptOccurrenceRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )

        let publicReceiptMutation = try receiptOccurrenceSection(
            in: ledgerSource,
            from: "public func recordApplicationUpdate(",
            to: "    /// Advances only the non-secret liveness observation"
        )

        #expect(!publicReceiptMutation.contains("isNonEmpty: Bool"),
                Comment(rawValue: "A caller must not combine an independently minted chronology token with a later assertion that a non-empty SDK application delivery occurred."))

        #expect(
            publicReceiptMutation.contains("delivery:") ||
            publicReceiptMutation.contains("admission:") ||
            publicReceiptMutation.contains("event:"),
            Comment(rawValue: "The package mutation should consume one opaque event/admission whose occurrence and monotonic delivery time were sealed together at the callback boundary."))
    }
}

private func receiptOccurrenceSection(
    in source: String,
    from start: String,
    to end: String
) throws -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        Issue.record("Expected application-delivery occurrence source section is missing.")
        throw ReceiptOccurrenceSourceContractError.sectionMissing
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

private func readReceiptOccurrenceRepositoryFile(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
}

private enum ReceiptOccurrenceSourceContractError: Error {
    case sectionMissing
}
