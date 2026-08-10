import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya local BLE acquisition window")
struct TuyaLocalBLEAcquisitionWindowTests {
    @Test("local online observation wins immediately")
    func observedOnlineWinsImmediately() {
        #expect(TuyaLocalBLEAcquisitionWindow.verdict(startedAtUptimeNanoseconds: 1_000, observedAtUptimeNanoseconds: 1_001, isLocallyOnline: true) == .observedOnline)
    }

    @Test("offline before deadline keeps waiting without minting auth")
    func waitsBeforeDeadline() {
        let start: UInt64 = 5_000
        #expect(TuyaLocalBLEAcquisitionWindow.verdict(startedAtUptimeNanoseconds: start, observedAtUptimeNanoseconds: start + TuyaLocalBLEAcquisitionWindow.maximumWaitNanoseconds - 1, isLocallyOnline: false) == .keepWaiting)
    }

    @Test("offline exactly at deadline fails closed")
    func deadlineIsFailClosed() {
        let start: UInt64 = 9_000
        #expect(TuyaLocalBLEAcquisitionWindow.verdict(startedAtUptimeNanoseconds: start, observedAtUptimeNanoseconds: start + TuyaLocalBLEAcquisitionWindow.maximumWaitNanoseconds, isLocallyOnline: false) == .timedOut)
    }

    @Test("online at deadline is still current evidence")
    func onlineAtDeadlineIsAccepted() {
        let start: UInt64 = 12_000
        #expect(TuyaLocalBLEAcquisitionWindow.verdict(startedAtUptimeNanoseconds: start, observedAtUptimeNanoseconds: start + TuyaLocalBLEAcquisitionWindow.maximumWaitNanoseconds, isLocallyOnline: true) == .observedOnline)
    }

    @Test("monotonic regression fails closed")
    func clockRegressionFailsClosed() {
        #expect(TuyaLocalBLEAcquisitionWindow.verdict(startedAtUptimeNanoseconds: 10_000, observedAtUptimeNanoseconds: 9_999, isLocallyOnline: false) == .invalidClock)
    }

    @Test("custom shorter window preserves exact boundary semantics")
    func customWindowBoundary() {
        #expect(TuyaLocalBLEAcquisitionWindow.verdict(startedAtUptimeNanoseconds: 100, observedAtUptimeNanoseconds: 149, isLocallyOnline: false, maximumWaitNanoseconds: 50) == .keepWaiting)
        #expect(TuyaLocalBLEAcquisitionWindow.verdict(startedAtUptimeNanoseconds: 100, observedAtUptimeNanoseconds: 150, isLocallyOnline: false, maximumWaitNanoseconds: 50) == .timedOut)
    }
}
