import Foundation
import Testing
@testable import NembraBluetoothCapture

extension TuyaApplicationReceiptChronologyTests {
    @Test("current ledger-issued application delivery is one-shot")
    func currentLedgerIssuedReceiptCannotReplayIntoRepeatedEvidence() async throws {
        let clock = CurrentReceiptReplayClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        clock.advance(to: 3_000)
        let receipt = try ledger.captureApplicationReceipt(isNonEmpty: true, for: token)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: receipt, for: token)
        let accepted = await ledger.currentPreflightSnapshot()
        #expect(accepted.applicationPayloadCount == 1)
        #expect(accepted.latestApplicationPayloadUptimeNanoseconds == 3_000)

        var duplicateRejected = false
        do {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: receipt, for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationAdmissionInvalidOrConsumed {
            duplicateRejected = true
        } catch {
            Issue.record("Unexpected duplicate-receipt error: \(error)")
        }

        #expect(duplicateRejected)
        let afterReplay = await ledger.currentPreflightSnapshot()
        #expect(afterReplay == accepted)
    }

    @Test("current shipping receipt authority belongs to exact ledger and has no token-only static factory")
    func currentReceiptAuthoritySourceIsLedgerOwned() throws {
        let source = try currentReceiptReplayRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )
        let receipt = try currentReceiptReplaySection(
            in: source,
            from: "public struct TuyaReadOnlyApplicationReceipt",
            to: "/// Opaque one-shot receipt for a direct current-connection liveness sample"
        )

        #expect(!receipt.contains("public static func capture"))
        #expect(!receipt.contains("public init("))
        #expect(receipt.contains("fileprivate let issuerID: UUID"))
        #expect(receipt.contains("fileprivate let deliverySequence: UInt64"))
        #expect(source.contains("nonisolated private let receiptAuthority: ReceiptAuthority"))
        #expect(source.contains("pendingApplicationSequences"))
        #expect(source.contains("pendingApplicationSequences.remove(receipt.deliverySequence) != nil"))
    }
}

private final class CurrentReceiptReplayClock: @unchecked Sendable {
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

private func currentReceiptReplaySection(in source: String, from start: String, to end: String) throws -> String {
    guard let a = source.range(of: start),
          let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
        Issue.record("Expected current receipt authority source section missing: \(start) ... \(end)")
        throw CurrentReceiptReplaySourceError.sectionMissing
    }
    return String(source[a.lowerBound..<b.lowerBound])
}

private func currentReceiptReplayRepositoryFile(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

private enum CurrentReceiptReplaySourceError: Error {
    case sectionMissing
}
