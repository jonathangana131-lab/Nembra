import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya exact-ledger application and liveness receipts")
struct TuyaApplicationReceiptChronologyTests {
    @Test("pre-cut application delivery remains pre-cut when actor admission happens after the deadline")
    func delayedApplicationAdmissionUsesLedgerDeliveryTime() async throws {
        let clock = ReceiptAuthorityTestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        let deliveredAt: UInt64 = 3_000
        clock.advance(to: deliveredAt)
        let receipt = try ledger.captureApplicationReceipt(isNonEmpty: true, for: token)

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

    @Test("one application receipt cannot be replayed into repeated physical-readiness count")
    func applicationReceiptIsOneShot() async throws {
        let clock = ReceiptAuthorityTestUptimeClock(10)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await authenticatedToken(ledger: ledger, clock: clock, base: 10)

        clock.advance(to: 20)
        let receipt = try ledger.captureApplicationReceipt(isNonEmpty: true, for: token)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: receipt, for: token)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationAdmissionInvalidOrConsumed) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: receipt, for: token)
        }
        #expect((await ledger.currentPreflightSnapshot()).applicationPayloadCount == 1)
    }

    @Test("pending application delivery prevents the package from issuing a later watchdog receipt")
    func packageArbitratesApplicationBeforeLiveness() async throws {
        let clock = ReceiptAuthorityTestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await authenticatedToken(ledger: ledger, clock: clock, base: 100)

        clock.advance(to: 110)
        let applicationReceipt = try ledger.captureApplicationReceipt(isNonEmpty: true, for: token)

        #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationAdmissionPending) {
            _ = try ledger.captureLivenessReceipt(for: token)
        }

        ledger.releaseApplicationReceipt(applicationReceipt)
        let livenessReceipt = try ledger.captureLivenessReceipt(for: token)
        try await ledger.observeCurrentConnection(receipt: livenessReceipt, for: token)
    }

    @Test("liveness delivery time stays in the ledger clock domain even if actor execution is delayed")
    func delayedLivenessAdmissionUsesLedgerDeliveryTime() async throws {
        let clock = ReceiptAuthorityTestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        let observedAt: UInt64 = 3_000
        clock.advance(to: observedAt)
        let receipt = try ledger.captureLivenessReceipt(for: token)
        clock.advance(
            to: 2_000
                + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
                + 10_000
        )
        try await ledger.observeCurrentConnection(receipt: receipt, for: token)

        #expect((await ledger.currentPreflightSnapshot()).latestObservedUptimeNanoseconds == observedAt)
    }

    @Test("an earlier liveness receipt finishing after a later application receipt is harmless and one-shot")
    func olderLivenessActorCompletionCannotRegressAcceptedApplicationChronology() async throws {
        let clock = ReceiptAuthorityTestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        clock.advance(to: 3_000)
        let acceptedPriorLiveness = try ledger.captureLivenessReceipt(for: token)
        try await ledger.observeCurrentConnection(receipt: acceptedPriorLiveness, for: token)

        clock.advance(to: 4_000)
        let earlierLiveness = try ledger.captureLivenessReceipt(for: token)
        clock.advance(to: 4_500)
        let laterApplication = try ledger.captureApplicationReceipt(isNonEmpty: true, for: token)

        // Deliberately execute the later actor mutation first to model actor scheduling inversion.
        try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: laterApplication, for: token)
        try await ledger.observeCurrentConnection(receipt: earlierLiveness, for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 4_500)
        #expect(snapshot.latestObservedUptimeNanoseconds == 4_500)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationAdmissionInvalidOrConsumed) {
            try await ledger.observeCurrentConnection(receipt: earlierLiveness, for: token)
        }
    }

    @Test("receipt from another exact ledger issuer cannot be consumed")
    func receiptCannotCrossLedgerIssuer() async throws {
        let clock = ReceiptAuthorityTestUptimeClock(1_000)
        let firstLedger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let firstToken = try await authenticatedToken(ledger: firstLedger, clock: clock, base: 1_000)
        clock.advance(to: 1_010)
        let foreignReceipt = try firstLedger.captureApplicationReceipt(isNonEmpty: true, for: firstToken)

        clock.advance(to: 2_000)
        let secondLedger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let secondToken = try await authenticatedToken(ledger: secondLedger, clock: clock, base: 2_000)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationAdmissionInvalidOrConsumed) {
            try await secondLedger.recordApplicationUpdate(
                isNonEmpty: true,
                receipt: foreignReceipt,
                for: secondToken
            )
        }
        #expect((await secondLedger.currentPreflightSnapshot()).applicationPayloadCount == 0)
        firstLedger.releaseApplicationReceipt(foreignReceipt)
    }

    @Test("application receipt delivered at the strict incomplete horizon cannot rescue the generation")
    func deadlineApplicationReceiptRemainsTerminal() async throws {
        let clock = ReceiptAuthorityTestUptimeClock(1_000)
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
            let liveness = try ledger.captureLivenessReceipt(for: token)
            try await ledger.observeCurrentConnection(receipt: liveness, for: token)
        }
        clock.advance(to: deadline - 1)
        let finalLiveness = try ledger.captureLivenessReceipt(for: token)
        try await ledger.observeCurrentConnection(receipt: finalLiveness, for: token)

        clock.advance(to: deadline)
        let receipt = try ledger.captureApplicationReceipt(isNonEmpty: true, for: token)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: receipt, for: token)
        }

        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.applicationPayloadCount == 0)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) != .readyForStationaryMapping)
        #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            _ = try ledger.captureLivenessReceipt(for: token)
        }
    }

    private func authenticatedToken(
        ledger: TuyaAuthenticatedReadOnlySessionLedger,
        clock: ReceiptAuthorityTestUptimeClock,
        base: UInt64
    ) async throws -> TuyaReadOnlyConnectionToken {
        clock.advance(to: base)
        let token = try await ledger.beginConnection()
        clock.advance(to: base + 1)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: base + 2)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        return token
    }
}

private final class ReceiptAuthorityTestUptimeClock: @unchecked Sendable {
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
