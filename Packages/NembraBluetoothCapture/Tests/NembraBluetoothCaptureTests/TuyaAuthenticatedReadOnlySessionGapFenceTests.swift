import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya session mutation-boundary continuity fence")
struct TuyaAuthenticatedReadOnlySessionGapFenceTests {
    @Test("queued application update cannot erase a long observation gap")
    func queuedUpdateAfterGapFailsBeforeAdvancingChronology() async throws {
        let clock = GapFenceClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        let beforeGap = await ledger.currentPreflightSnapshot()

        clock.advance(to: 2_000 + TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }

        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Authenticated observation continuity was invalidated by a long observation gap."))
        #expect(failed.authenticationMethod == .smartLifeAppSDK)
        #expect(failed.authenticatedAtUptimeNanoseconds == 2_000)
        #expect(failed.applicationPayloadCount == 0)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == nil)
        #expect(failed.latestObservedUptimeNanoseconds == beforeGap.latestObservedUptimeNanoseconds)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) == .blocked(reason: "Authenticated observation continuity was invalidated by a long observation gap."))
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
    }

    @Test("exact five-second gap is admitted")
    func exactGapBoundaryIsAccepted() async throws {
        let clock = GapFenceClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 200 + TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .authenticated)
        #expect(snapshot.applicationPayloadCount == 1)
    }

    @Test("prior legitimate application evidence survives a later continuity invalidation as diagnostics")
    func gapPreservesEarnedHistoryButRevokesAuthority() async throws {
        let clock = GapFenceClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        let earned = await ledger.currentPreflightSnapshot()

        clock.advance(to: 300 + TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated) {
            try await ledger.observeCurrentConnection(for: token)
        }
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationMethod == earned.authenticationMethod)
        #expect(failed.authenticatedAtUptimeNanoseconds == earned.authenticatedAtUptimeNanoseconds)
        #expect(failed.applicationPayloadCount == 1)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == earned.latestApplicationPayloadUptimeNanoseconds)
        #expect(failed.latestObservedUptimeNanoseconds == earned.latestObservedUptimeNanoseconds)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) == .blocked(reason: "Authenticated observation continuity was invalidated by a long observation gap."))
    }
}

private final class GapFenceClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64
    init(_ value: UInt64) { self.value = value }
    var now: @Sendable () -> UInt64 {
        { [self] in lock.lock(); defer { lock.unlock() }; return value }
    }
    func advance(to newValue: UInt64) { lock.lock(); value = newValue; lock.unlock() }
}
