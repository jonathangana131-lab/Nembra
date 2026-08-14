import Dispatch
import Foundation
import Testing
@testable import NembraBluetoothCapture

extension TuyaAuthenticatedReadOnlySessionLedgerTests {
    @Test("pending delivery arbitrates ahead of delayed watchdog liveness")
    func ledgerIssuedReceiptBlocksWatchdogOvertake() async throws {
        let clock = LedgerIssuedReceiptTestClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        let second: UInt64 = 1_000_000_000
        var offset: UInt64 = 5 * second
        while offset <= 55 * second {
            clock.advance(to: 1_000 + offset)
            try await ledger.observeCurrentConnection(for: token)
            offset += 5 * second
        }
        clock.advance(to: 1_000 + 59 * second)
        try await ledger.observeCurrentConnection(for: token)

        let receipt = ledger.captureApplicationReceipt(for: token)
        clock.advance(to: 1_000 + 65 * second)

        // This watchdog call is deliberately beyond both the incomplete-session horizon
        // and the continuity gap. Because delivery already won the package arbiter, it
        // must yield without sampling/mutating either boundary.
        try await ledger.observeCurrentConnection(for: token)
        let beforeAdmission = await ledger.currentPreflightSnapshot()
        #expect(beforeAdmission.applicationPayloadCount == 0)
        #expect(beforeAdmission.latestObservedUptimeNanoseconds == 1_000 + 59 * second)

        try await ledger.recordApplicationUpdate(
            isNonEmpty: true,
            receipt: receipt,
            for: token
        )
        let accepted = await ledger.currentPreflightSnapshot()
        #expect(accepted.applicationPayloadCount == 1)
        #expect(accepted.latestApplicationPayloadUptimeNanoseconds == 1_000 + 59 * second)
        #expect(accepted.latestObservedUptimeNanoseconds == 1_000 + 59 * second)
    }

    @Test("ledger receipt uses the injected monotonic authority domain")
    func ledgerReceiptSharesInjectedMonotonicClock() async throws {
        let clock = LedgerIssuedReceiptTestClock(50_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        clock.advance(to: 77_777)
        let receipt = ledger.captureApplicationReceipt(for: token)
        try await ledger.recordApplicationUpdate(
            isNonEmpty: true,
            receipt: receipt,
            for: token
        )

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 77_777)
        #expect(snapshot.latestObservedUptimeNanoseconds == 77_777)
    }

    @Test("one ledger-issued delivery receipt cannot be replayed into readiness count")
    func ledgerReceiptIsOneShot() async throws {
        let clock = LedgerIssuedReceiptTestClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        let receipt = ledger.captureApplicationReceipt(for: token)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: receipt, for: token)
        await #expect(
            throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationDeliveryReceiptAlreadyConsumed
        ) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: receipt, for: token)
        }

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
    }

    @Test("receipt from another exact ledger cannot cross issuer and token authority")
    func crossLedgerReceiptIsRejected() async throws {
        let first = TuyaAuthenticatedReadOnlySessionLedger()
        let second = TuyaAuthenticatedReadOnlySessionLedger()
        let firstToken = try await first.beginConnection()
        let secondToken = try await second.beginConnection()
        try await second.markAuthenticationStarted(for: secondToken)
        try await second.markAuthenticated(for: secondToken, method: .smartLifeAppSDK)

        let foreignReceipt = first.captureApplicationReceipt(for: firstToken)
        await #expect(
            throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.invalidApplicationReceipt
        ) {
            try await second.recordApplicationUpdate(
                isNonEmpty: true,
                receipt: foreignReceipt,
                for: secondToken
            )
        }

        let snapshot = await second.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 0)
    }

    @Test("post-cut ledger-issued receipt remains terminally rejected")
    func postCutLedgerReceiptCannotRescueIncompleteGeneration() async throws {
        let clock = LedgerIssuedReceiptTestClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        let second: UInt64 = 1_000_000_000
        var offset: UInt64 = 5 * second
        while offset <= 55 * second {
            clock.advance(to: 1_000 + offset)
            try await ledger.observeCurrentConnection(for: token)
            offset += 5 * second
        }
        clock.advance(to: 1_000 + 59 * second)
        try await ledger.observeCurrentConnection(for: token)
        clock.advance(
            to: 1_000
                + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
                + 1
        )
        let lateReceipt = ledger.captureApplicationReceipt(for: token)

        await #expect(
            throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached
        ) {
            try await ledger.recordApplicationUpdate(
                isNonEmpty: true,
                receipt: lateReceipt,
                for: token
            )
        }

        let terminal = await ledger.currentPreflightSnapshot()
        #expect(terminal.applicationPayloadCount == 0)
        if case .failed = terminal.authenticationState {
        } else {
            Issue.record("Post-cut receipt must retire the incomplete generation.")
        }
    }

    @Test("receipt source has no public constructor or static mint surface")
    func ledgerReceiptSurfaceIsOpaqueAndLedgerIssued() throws {
        let source = try readLedgerIssuedReceiptRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )
        let receipt = try ledgerIssuedReceiptSection(
            in: source,
            from: "public struct TuyaReadOnlyApplicationReceipt",
            to: "public actor TuyaAuthenticatedReadOnlySessionLedger"
        )
        let record = try ledgerIssuedReceiptSection(
            in: source,
            from: "public func recordApplicationUpdate(",
            to: "public func observeCurrentConnection("
        )

        #expect(receipt.contains("fileprivate let token: TuyaReadOnlyConnectionToken"))
        #expect(receipt.contains("fileprivate let issuerID: UUID"))
        #expect(receipt.contains("fileprivate let deliveryID: UUID"))
        #expect(receipt.contains("fileprivate let receivedAtUptimeNanoseconds: UInt64"))
        #expect(!receipt.contains("public init("))
        #expect(!receipt.contains("public static func capture"))
        #expect(source.contains("public nonisolated func captureApplicationReceipt("))
        #expect(source.contains("consumedApplicationDeliveryIDs.insert(receipt.deliveryID).inserted"))
        #expect(record.contains("receipt.issuerID == applicationReceiptIssuerID"))
        #expect(record.contains("let now = receipt.receivedAtUptimeNanoseconds"))
        #expect(!record.contains("receivedAtUptimeNanoseconds: UInt64"))
        #expect(!record.contains("let now = try nextMonotonicObservation()"))
    }
}

private final class LedgerIssuedReceiptTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }

    var now: @Sendable () -> UInt64 {
        { [self] in
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    func advance(to newValue: UInt64) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

private func ledgerIssuedReceiptSection(in source: String, from start: String, to end: String) throws -> String {
    guard let a = source.range(of: start),
          let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
        Issue.record("Expected ledger-issued receipt source section missing: \(start) ... \(end)")
        throw LedgerIssuedReceiptSourceError.sectionMissing
    }
    return String(source[a.lowerBound..<b.lowerBound])
}

private func readLedgerIssuedReceiptRepositoryFile(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

private enum LedgerIssuedReceiptSourceError: Error {
    case sectionMissing
}
