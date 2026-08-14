import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application delivery receipts")
struct TuyaApplicationReceiptChronologyTests {
    @Test("pre-cut delivery remains pre-cut when actor admission happens after the deadline")
    func delayedAdmissionUsesOpaqueDeliveryTime() async throws {
        let clock = ReceiptTestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        let deliveredAt: UInt64 = 3_000
        let receipt = TuyaReadOnlyApplicationReceipt.testingCapture(
            for: token,
            receivedAtUptimeNanoseconds: deliveredAt
        )
        clock.advance(
            to: 2_000
                + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
                + 10_000
        )

        try await ledger.recordApplicationUpdate(
            isNonEmpty: true,
            receipt: receipt,
            for: token
        )
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == deliveredAt)
        #expect(snapshot.latestObservedUptimeNanoseconds == deliveredAt)
    }

    @Test("receipt is bound to the exact connection token")
    func receiptCannotCrossConnectionGeneration() async throws {
        let clock = ReceiptTestUptimeClock(10)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let first = try await ledger.beginConnection()
        let staleReceipt = TuyaReadOnlyApplicationReceipt.testingCapture(
            for: first,
            receivedAtUptimeNanoseconds: 11
        )

        clock.advance(to: 20)
        let second = try await ledger.beginConnection()
        clock.advance(to: 25)
        try await ledger.markAuthenticationStarted(for: second)
        clock.advance(to: 30)
        try await ledger.markAuthenticated(for: second, method: .smartLifeAppSDK)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection) {
            try await ledger.recordApplicationUpdate(
                isNonEmpty: true,
                receipt: staleReceipt,
                for: second
            )
        }
        #expect((await ledger.currentPreflightSnapshot()).applicationPayloadCount == 0)
    }

    @Test("receipt delivered at the strict incomplete horizon cannot rescue an incomplete generation")
    func deadlineReceiptRemainsTerminal() async throws {
        let clock = ReceiptTestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        let authenticatedAt: UInt64 = 2_000
        clock.advance(to: authenticatedAt)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        let deadline = authenticatedAt
            + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
        var cursor = authenticatedAt
        let step = TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds - 1
        while cursor + step < deadline {
            cursor += step
            clock.advance(to: cursor)
            try await ledger.observeCurrentConnection(for: token)
        }
        let finalLiveness = deadline - 1
        clock.advance(to: finalLiveness)
        try await ledger.observeCurrentConnection(for: token)

        let receipt = TuyaReadOnlyApplicationReceipt.testingCapture(
            for: token,
            receivedAtUptimeNanoseconds: deadline
        )
        clock.advance(to: deadline + 5_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached) {
            try await ledger.recordApplicationUpdate(
                isNonEmpty: true,
                receipt: receipt,
                for: token
            )
        }
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.applicationPayloadCount == 0)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) != .readyForStationaryMapping)
    }
}

private final class ReceiptTestUptimeClock: @unchecked Sendable {
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
