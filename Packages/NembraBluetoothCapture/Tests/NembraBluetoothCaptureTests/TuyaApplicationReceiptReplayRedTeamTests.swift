import Foundation
import Testing
@testable import NembraBluetoothCapture

extension TuyaApplicationReceiptChronologyTests {
    @Test("one delivered application receipt cannot satisfy repeated-observation evidence twice")
    func oneReceiptCannotBeReplayedIntoTwoApplicationObservations() async throws {
        let clock = ApplicationReceiptReplayClock(1_000)
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

        // A repaired ledger may reject the duplicate with a dedicated mutation error. The exact
        // error spelling is not the authority here; the invariant is that a single physical SDK
        // delivery can advance application evidence at most once.
        do {
            try await ledger.recordApplicationUpdate(
                isNonEmpty: true,
                receipt: receipt,
                for: token
            )
        } catch {
            // Expected for a one-shot receipt implementation.
        }

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 3_000)
    }

    @Test("shipping receipt surface is not a public token-only mint factory")
    func receiptMintingAuthorityBelongsToExactLedgerInstance() throws {
        let source = try applicationReceiptReplayRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )
        let receipt = try applicationReceiptReplaySection(
            in: source,
            from: "public struct TuyaReadOnlyApplicationReceipt",
            to: "public actor TuyaAuthenticatedReadOnlySessionLedger"
        )

        #expect(!receipt.contains("public static func capture(for token: TuyaReadOnlyConnectionToken)"))
        #expect(receipt.contains("fileprivate let issuerID: UUID"))
        #expect(receipt.contains("fileprivate let deliveryID: UUID"))
        #expect(source.contains("applicationReceiptIssuerID"))
        #expect(source.contains("consumedApplicationDeliveryIDs"))
    }
}

private final class ApplicationReceiptReplayClock: @unchecked Sendable {
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

private func applicationReceiptReplaySection(in source: String, from start: String, to end: String) throws -> String {
    guard let a = source.range(of: start),
          let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
        Issue.record("Expected application-receipt source section missing: \(start) ... \(end)")
        throw ApplicationReceiptReplaySourceError.sectionMissing
    }
    return String(source[a.lowerBound..<b.lowerBound])
}

private func applicationReceiptReplayRepositoryFile(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

private enum ApplicationReceiptReplaySourceError: Error {
    case sectionMissing
}
