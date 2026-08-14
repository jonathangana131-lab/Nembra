import Foundation
import Testing
@testable import NembraBluetoothCapture

extension TuyaApplicationReceiptChronologyTests {
    @Test("one delivered application receipt cannot mint repeated evidence twice")
    func duplicateApplicationReceiptIsRejectedBeforeCountMoves() async throws {
        let clock = ReceiptAuthorityTestClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        let receipt = TuyaReadOnlyApplicationReceipt.testingCapture(
            for: token,
            receivedAtUptimeNanoseconds: 3_000
        )

        try await ledger.recordApplicationUpdate(
            isNonEmpty: true,
            receipt: receipt,
            for: token
        )

        var duplicateWasRejected = false
        do {
            try await ledger.recordApplicationUpdate(
                isNonEmpty: true,
                receipt: receipt,
                for: token
            )
        } catch {
            duplicateWasRejected = true
        }

        #expect(duplicateWasRejected,
                Comment(rawValue: "A one-shot physical-readiness delivery must not be replayable into the repeated-payload count."))
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1,
                Comment(rawValue: "Replaying one application delivery must never manufacture a second accepted observation."))
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 3_000)
    }

    @Test("production delivery authority cannot be minted from a token and later paired with caller-selected payload presence")
    func shippingAPISealsDeliveryOccurrenceWithChronology() throws {
        let ledgerSource = try readReceiptAuthorityRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )

        #expect(!ledgerSource.contains("public static func capture(for token:"),
                Comment(rawValue: "A valid connection token alone must not be sufficient to pre-mint a timestamped application-delivery authority."))

        let publicReceiptMutation = try receiptAuthoritySection(
            in: ledgerSource,
            from: "public func recordApplicationUpdate(",
            to: "    /// Advances only the non-secret liveness observation"
        )
        #expect(!publicReceiptMutation.contains("isNonEmpty: Bool"),
                Comment(rawValue: "The caller must not separately combine a timestamp authority with a later assertion that a non-empty application delivery occurred."))
    }
}

private final class ReceiptAuthorityTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }

    func now() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(to newValue: UInt64) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

private func receiptAuthoritySection(
    in source: String,
    from start: String,
    to end: String
) throws -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        Issue.record("Expected application-receipt authority source section is missing.")
        throw ReceiptAuthoritySourceContractError.sectionMissing
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

private func readReceiptAuthorityRepositoryFile(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
}

private enum ReceiptAuthoritySourceContractError: Error {
    case sectionMissing
}
