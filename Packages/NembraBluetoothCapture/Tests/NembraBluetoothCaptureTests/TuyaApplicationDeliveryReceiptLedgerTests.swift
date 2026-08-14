import Dispatch
import Foundation
import Testing
@testable import NembraBluetoothCapture

extension TuyaAuthenticatedReadOnlySessionLedgerTests {
    @Test("opaque receipt preserves callback delivery time across delayed actor admission")
    func applicationReceiptPreservesDeliveryInstant() async throws {
        let baseline = DispatchTime.now().uptimeNanoseconds
        let clock = DeliveryReceiptTestUptimeClock(baseline)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        let receipt = TuyaReadOnlyApplicationReceipt.capture(for: token)

        // Move the actor's injected execution clock beyond the strict incomplete-session
        // horizon. The explicit receipt path must still evaluate the already-delivered
        // callback at its earlier package-owned receipt instant rather than this later
        // actor execution time.
        clock.advance(
            to: baseline
                + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
                + 1
        )
        try await ledger.recordApplicationUpdate(
            isNonEmpty: true,
            receipt: receipt,
            for: token
        )

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        let payloadTime = try #require(snapshot.latestApplicationPayloadUptimeNanoseconds)
        #expect(payloadTime >= baseline)
        #expect(
            payloadTime - baseline
                < TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
        )
    }

    @Test("a genuinely post-cut package receipt still retires incomplete observation")
    func postCutApplicationReceiptCannotRescueGeneration() async throws {
        let realNow = DispatchTime.now().uptimeNanoseconds
        let horizon = TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
        let oneSecond: UInt64 = 1_000_000_000
        let fiveSeconds: UInt64 = 5_000_000_000

        // Authenticate 61 seconds before the package-owned receipt clock. Advance accepted
        // liveness in <=5-second steps only through +59 seconds, so continuity remains valid while
        // canonical readiness remains incomplete. The later real DispatchTime receipt is therefore
        // genuinely beyond the strict 60-second horizon and must terminalize rather than rescue it.
        let authenticatedBaseline = realNow - horizon - oneSecond
        let clock = DeliveryReceiptTestUptimeClock(authenticatedBaseline)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        var offset = fiveSeconds
        while offset <= 55 * oneSecond {
            clock.advance(to: authenticatedBaseline + offset)
            try await ledger.observeCurrentConnection(for: token)
            offset += fiveSeconds
        }
        clock.advance(to: authenticatedBaseline + 59 * oneSecond)
        try await ledger.observeCurrentConnection(for: token)

        let postCutReceipt = TuyaReadOnlyApplicationReceipt.capture(for: token)
        await #expect(
            throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached
        ) {
            try await ledger.recordApplicationUpdate(
                isNonEmpty: true,
                receipt: postCutReceipt,
                for: token
            )
        }

        let terminal = await ledger.currentPreflightSnapshot()
        #expect(terminal.applicationPayloadCount == 0)
        #expect(terminal.latestApplicationPayloadUptimeNanoseconds == nil)
        if case .failed = terminal.authenticationState {
            // Expected package-owned terminal; no disconnect claim is manufactured here.
        } else {
            Issue.record("Post-cut receipt must leave the generation terminally failed.")
        }
    }

    @Test("application receipt cannot cross exact connection-token ownership")
    func applicationReceiptIsBoundToExactConnectionToken() async throws {
        let firstLedger = TuyaAuthenticatedReadOnlySessionLedger()
        let secondLedger = TuyaAuthenticatedReadOnlySessionLedger()
        let first = try await firstLedger.beginConnection()
        let second = try await secondLedger.beginConnection()
        try await secondLedger.markAuthenticationStarted(for: second)
        try await secondLedger.markAuthenticated(for: second, method: .smartLifeAppSDK)

        let foreignReceipt = TuyaReadOnlyApplicationReceipt.capture(for: first)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection) {
            try await secondLedger.recordApplicationUpdate(
                isNonEmpty: true,
                receipt: foreignReceipt,
                for: second
            )
        }

        let snapshot = await secondLedger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 0)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == nil)
    }

    @Test("receipt source surface exposes no caller-selected timestamp initializer")
    func applicationReceiptSourceIsOpaqueAndPackageTimed() throws {
        let source = try readDeliveryReceiptRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )
        let receipt = try deliveryReceiptSection(
            in: source,
            from: "public struct TuyaReadOnlyApplicationReceipt",
            to: "public actor TuyaAuthenticatedReadOnlySessionLedger"
        )
        let mutation = try deliveryReceiptSection(
            in: source,
            from: "public func recordApplicationUpdate(",
            to: "public func observeCurrentConnection("
        )

        #expect(receipt.contains("fileprivate let token: TuyaReadOnlyConnectionToken"))
        #expect(receipt.contains("fileprivate let receivedAtUptimeNanoseconds: UInt64"))
        #expect(receipt.contains("public static func capture(for token: TuyaReadOnlyConnectionToken)"))
        #expect(receipt.contains("DispatchTime.now().uptimeNanoseconds"))
        #expect(!receipt.contains("public init("))
        #expect(!receipt.contains("public static func capture(for token: TuyaReadOnlyConnectionToken, receivedAtUptimeNanoseconds:"))

        #expect(mutation.contains("receipt: TuyaReadOnlyApplicationReceipt"))
        #expect(mutation.contains("receipt.token == token"))
        #expect(mutation.contains("let now = receipt.receivedAtUptimeNanoseconds"))
        #expect(mutation.contains("try requireContinuousAuthenticatedObservation(at: now)"))
        #expect(mutation.contains("try requireIncompleteObservationHorizonOpen(at: now)"))
        #expect(!mutation.contains("public func recordApplicationUpdate(\n        isNonEmpty: Bool,\n        receipt: TuyaReadOnlyApplicationReceipt,\n        receivedAtUptimeNanoseconds:"))
    }
}

private final class DeliveryReceiptTestUptimeClock: @unchecked Sendable {
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

private func deliveryReceiptSection(in source: String, from start: String, to end: String) throws -> String {
    guard let a = source.range(of: start),
          let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
        Issue.record("Expected delivery-receipt source section missing: \(start) ... \(end)")
        throw DeliveryReceiptSourceError.sectionMissing
    }
    return String(source[a.lowerBound..<b.lowerBound])
}

private func readDeliveryReceiptRepositoryFile(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

private enum DeliveryReceiptSourceError: Error {
    case sectionMissing
}
