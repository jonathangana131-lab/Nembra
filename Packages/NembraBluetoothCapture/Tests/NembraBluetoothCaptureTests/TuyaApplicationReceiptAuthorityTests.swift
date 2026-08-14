import Foundation
import Testing
@testable import NembraBluetoothCapture

extension TuyaAuthenticatedReadOnlySessionLedgerTests {
    @Test("application receipts are exact-ledger one-shot authority")
    func applicationReceiptRejectsCrossLedgerAndReplay() async throws {
        let firstClock = ApplicationReceiptLockedClock(0)
        let firstLedger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: firstClock.now)
        let firstToken = try await authenticatedApplicationReceiptToken(ledger: firstLedger, clock: firstClock)

        firstClock.set(3_000_000_000)
        let receipt = try #require(firstLedger.captureApplicationReceipt(for: firstToken))
        try await firstLedger.recordApplicationUpdate(isNonEmpty: true, receipt: receipt, for: firstToken)
        let accepted = await firstLedger.currentPreflightSnapshot()
        #expect(accepted.applicationPayloadCount == 1)
        #expect(accepted.latestApplicationPayloadUptimeNanoseconds == 3_000_000_000)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.duplicateApplicationReceipt) {
            try await firstLedger.recordApplicationUpdate(isNonEmpty: true, receipt: receipt, for: firstToken)
        }
        let afterReplay = await firstLedger.currentPreflightSnapshot()
        #expect(afterReplay.applicationPayloadCount == 1)
        #expect(afterReplay.latestApplicationPayloadUptimeNanoseconds == 3_000_000_000)

        let secondClock = ApplicationReceiptLockedClock(0)
        let secondLedger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: secondClock.now)
        let secondToken = try await authenticatedApplicationReceiptToken(ledger: secondLedger, clock: secondClock)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.invalidApplicationReceipt) {
            try await secondLedger.recordApplicationUpdate(isNonEmpty: true, receipt: receipt, for: secondToken)
        }
        let foreign = await secondLedger.currentPreflightSnapshot()
        #expect(foreign.applicationPayloadCount == 0)
    }

    @Test("receipt capture and actor consumption share one injected monotonic clock")
    func applicationReceiptUsesLedgerClockDomain() async throws {
        let clock = ApplicationReceiptLockedClock(0)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await authenticatedApplicationReceiptToken(ledger: ledger, clock: clock)

        clock.set(3_000_000_000)
        let receipt = try #require(ledger.captureApplicationReceipt(for: token))

        // Actor execution occurs much later. If recordApplicationUpdate resampled another clock,
        // this would cross both continuity and the bounded incomplete-observation horizon.
        clock.set(100_000_000_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: receipt, for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 3_000_000_000)
        #expect(snapshot.latestObservedUptimeNanoseconds == 3_000_000_000)
        #expect(snapshot.authenticationState == .authenticated)
    }

    @Test("later callback task cannot consume ahead of an earlier delivered receipt")
    func applicationReceiptsConsumeInDeliveryOrder() async throws {
        let clock = ApplicationReceiptLockedClock(0)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await authenticatedApplicationReceiptToken(ledger: ledger, clock: clock)

        clock.set(3_000_000_000)
        let first = try #require(ledger.captureApplicationReceipt(for: token))
        clock.set(4_000_000_000)
        let second = try #require(ledger.captureApplicationReceipt(for: token))

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationReceiptOrderPending) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: second, for: token)
        }
        #expect((await ledger.currentPreflightSnapshot()).applicationPayloadCount == 0)

        try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: first, for: token)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: second, for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 2)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 4_000_000_000)
        #expect(snapshot.latestObservedUptimeNanoseconds == 4_000_000_000)
    }

    @Test("package liveness cannot overtake an already delivered application receipt")
    func livenessWaitsForPendingApplicationReceipt() async throws {
        let clock = ApplicationReceiptLockedClock(0)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await authenticatedApplicationReceiptToken(ledger: ledger, clock: clock)

        clock.set(3_000_000_000)
        let receipt = try #require(ledger.captureApplicationReceipt(for: token))
        clock.set(4_000_000_000)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationReceiptPending) {
            try await ledger.observeCurrentConnection(for: token)
        }
        #expect((await ledger.currentPreflightSnapshot()).latestObservedUptimeNanoseconds == 2_000_000_000)

        try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: receipt, for: token)
        try await ledger.observeCurrentConnection(for: token)
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.latestObservedUptimeNanoseconds == 4_000_000_000)
        #expect(snapshot.applicationPayloadCount == 1)
    }

    @Test("two pre-cut deliveries cannot be overtaken by a post-cut watchdog mutation")
    func deliveredReadyPrefixWinsOverLaterWatchdogScheduling() async throws {
        let clock = ApplicationReceiptLockedClock(0)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await authenticatedApplicationReceiptToken(ledger: ledger, clock: clock)

        for uptime in stride(from: UInt64(6_000_000_000), through: 58_000_000_000, by: 4_000_000_000) {
            clock.set(uptime)
            try await ledger.observeCurrentConnection(for: token)
        }

        clock.set(59_000_000_000)
        let first = try #require(ledger.captureApplicationReceipt(for: token))
        clock.set(61_500_000_000)
        let second = try #require(ledger.captureApplicationReceipt(for: token))

        // The watchdog reaches the actor only after the 60-second absolute horizon. Both app
        // deliveries were already synchronously receipted before it, so package arbitration must
        // refuse to let liveness terminalize the generation ahead of that pending prefix.
        clock.set(62_500_000_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationReceiptPending) {
            try await ledger.observeCurrentConnection(for: token)
        }

        try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: first, for: token)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: second, for: token)
        try await ledger.observeCurrentConnection(for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 2)
        #expect(snapshot.authenticationState == .authenticated)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping)
    }

    @Test("genuinely post-cut application delivery cannot rescue an incomplete generation")
    func postCutDeliveryStillFailsClosed() async throws {
        let clock = ApplicationReceiptLockedClock(0)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await authenticatedApplicationReceiptToken(ledger: ledger, clock: clock)

        for uptime in stride(from: UInt64(6_000_000_000), through: 58_000_000_000, by: 4_000_000_000) {
            clock.set(uptime)
            try await ledger.observeCurrentConnection(for: token)
        }

        clock.set(62_100_000_000)
        let late = try #require(ledger.captureApplicationReceipt(for: token))
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, receipt: late, for: token)
        }

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 0)
        #expect(snapshot.authenticationState == .failed(
            reason: "Authenticated session ended because required repeated application evidence did not become sufficient before the observation deadline."
        ))
        #expect(ledger.captureApplicationReceipt(for: token) == nil)
    }

    private func authenticatedApplicationReceiptToken(
        ledger: TuyaAuthenticatedReadOnlySessionLedger,
        clock: ApplicationReceiptLockedClock
    ) async throws -> TuyaReadOnlyConnectionToken {
        let token = try await ledger.beginConnection()
        clock.set(1_000_000_000)
        try await ledger.markAuthenticationStarted(for: token)
        clock.set(2_000_000_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        return token
    }
}

private final class ApplicationReceiptLockedClock: @unchecked Sendable {
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

    func set(_ newValue: UInt64) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}
