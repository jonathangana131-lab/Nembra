import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated observation continuity")
struct TuyaAuthenticatedReadOnlySessionContinuityTests {
    @Test("queued application update cannot erase a long observation gap")
    func queuedUpdateAfterGapFailsBeforeAdvancingChronology() async throws {
        let clock = ContinuityTestClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
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
        #expect(failed.applicationPayloadCount == 0)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == nil)
        #expect(failed.latestObservedUptimeNanoseconds == beforeGap.latestObservedUptimeNanoseconds)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) == .blocked(reason: "Authenticated observation continuity was invalidated by a long observation gap."))

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
    }

    @Test("exact maximum observation gap remains admitted")
    func exactGapBoundaryIsAccepted() async throws {
        let clock = ContinuityTestClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 150)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        let boundary = 200 + TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds
        clock.advance(to: boundary)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .authenticated)
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == boundary)
        #expect(snapshot.latestObservedUptimeNanoseconds == boundary)
    }

    @Test("liveness poll after a long observation gap retires authority")
    func livenessAfterGapFailsClosed() async throws {
        let clock = ContinuityTestClock(10)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 15)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 20)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        clock.advance(to: 20 + TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated) {
            try await ledger.observeCurrentConnection(for: token)
        }

        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Authenticated observation continuity was invalidated by a long observation gap."))
        #expect(failed.latestObservedUptimeNanoseconds == 20)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
    }

    @Test("explicit continuity invalidation preserves last legitimate observation")
    func explicitInvalidationPreservesHistory() async throws {
        let clock = ContinuityTestClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 150)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 6_000_000_300)
        try await ledger.markObservationContinuityInvalidated(for: token)

        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Authenticated observation continuity was interrupted."))
        #expect(failed.authenticationMethod == .smartLifeAppSDK)
        #expect(failed.applicationPayloadCount == 1)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == 300)
        #expect(failed.latestObservedUptimeNanoseconds == 300)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) == .blocked(reason: "Authenticated observation continuity was interrupted."))
    }
}

private final class ContinuityTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) { self.value = value }

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
