import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya Device Sharing provenance")
struct TuyaDeviceSharingAuthenticationAuthorityTests {
    @Test("Device Sharing is not BLE authentication provenance")
    func deviceSharingDoesNotAuthenticateBLEGeneration() async throws {
        let clock = DeviceSharingTestClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        let before = await ledger.currentPreflightSnapshot()

        clock.advance(to: 2_000)
        var didReject = false
        do {
            try await ledger.markAuthenticated(for: token, method: .documentedDeviceSharing)
        } catch {
            didReject = true
        }

        let after = await ledger.currentPreflightSnapshot()
        #expect(didReject)
        #expect(after.authenticationState == before.authenticationState)
        #expect(after.authenticationMethod == before.authenticationMethod)
        #expect(after.authenticatedAtUptimeNanoseconds == before.authenticatedAtUptimeNanoseconds)
    }
}

private final class DeviceSharingTestClock: @unchecked Sendable {
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
