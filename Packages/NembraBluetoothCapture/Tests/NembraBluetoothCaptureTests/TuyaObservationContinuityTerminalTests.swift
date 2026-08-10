import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya observation continuity terminal")
struct TuyaObservationContinuityTerminalTests {
    @Test("continuity invalidation preserves earned evidence and retires callback authority")
    func continuityInvalidationIsTerminal() async throws {
        let clock = ContinuityTestClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        let before = await ledger.currentPreflightSnapshot()

        clock.advance(to: 9_000)
        try await ledger.markObservationContinuityInvalidated(for: token)
        let terminal = await ledger.currentPreflightSnapshot()

        #expect(terminal.authenticationState == .failed(reason: "Authenticated observation continuity was invalidated."))
        #expect(terminal.authenticationMethod == .smartLifeAppSDK)
        #expect(terminal.connectionStartedAtUptimeNanoseconds == before.connectionStartedAtUptimeNanoseconds)
        #expect(terminal.authenticatedAtUptimeNanoseconds == before.authenticatedAtUptimeNanoseconds)
        #expect(terminal.applicationPayloadCount == before.applicationPayloadCount)
        #expect(terminal.latestApplicationPayloadUptimeNanoseconds == before.latestApplicationPayloadUptimeNanoseconds)
        #expect(terminal.latestObservedUptimeNanoseconds == 9_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: terminal) == .blocked(reason: "Authenticated observation continuity was invalidated."))

        clock.advance(to: 10_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == terminal)
    }

    @Test("ordinary connection end remains distinct from observation invalidation")
    func connectionEndKeepsDisconnectSemantics() async throws {
        let clock = ContinuityTestClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 200)
        try await ledger.endConnection(for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .unavailable(reason: "Bluetooth connection ended."))
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
