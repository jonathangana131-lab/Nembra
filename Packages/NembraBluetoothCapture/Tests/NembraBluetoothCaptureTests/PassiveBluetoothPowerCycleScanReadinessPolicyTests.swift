import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth power-cycle scan readiness")
struct PassiveBluetoothPowerCycleScanReadinessPolicyTests {
    @Test("a scan request may wait while powered on before the readiness deadline")
    func requestDoesNotRequireSynchronousScanning() {
        let decision = PassiveBluetoothPowerCycleScanReadinessPolicy.decide(
            isPoweredOn: true,
            isScanning: false,
            nowUptimeNanoseconds: 100,
            deadlineUptimeNanoseconds: 200
        )

        #expect(decision == .wait)
    }

    @Test("observed scanning becomes ready before the deadline")
    func observedScanningBecomesReady() {
        let decision = PassiveBluetoothPowerCycleScanReadinessPolicy.decide(
            isPoweredOn: true,
            isScanning: true,
            nowUptimeNanoseconds: 100,
            deadlineUptimeNanoseconds: 200
        )

        #expect(decision == .ready)
    }

    @Test("readiness expires exactly at the deadline")
    func readinessDeadlineIsFailClosed() {
        let decision = PassiveBluetoothPowerCycleScanReadinessPolicy.decide(
            isPoweredOn: true,
            isScanning: false,
            nowUptimeNanoseconds: 200,
            deadlineUptimeNanoseconds: 200
        )

        #expect(decision == .timedOut)
    }

    @Test("a first scanning observation at the deadline is too late")
    func lateScanningCannotCrossDeadline() {
        let decision = PassiveBluetoothPowerCycleScanReadinessPolicy.decide(
            isPoweredOn: true,
            isScanning: true,
            nowUptimeNanoseconds: 200,
            deadlineUptimeNanoseconds: 200
        )

        #expect(decision == .timedOut)
    }

    @Test("a first scanning observation after the deadline is too late")
    func scanningAfterDeadlineCannotBecomeReady() {
        let decision = PassiveBluetoothPowerCycleScanReadinessPolicy.decide(
            isPoweredOn: true,
            isScanning: true,
            nowUptimeNanoseconds: 201,
            deadlineUptimeNanoseconds: 200
        )

        #expect(decision == .timedOut)
    }

    @Test("Bluetooth authority loss dominates an apparent scanning flag")
    func poweredOffCannotBecomeReady() {
        let decision = PassiveBluetoothPowerCycleScanReadinessPolicy.decide(
            isPoweredOn: false,
            isScanning: true,
            nowUptimeNanoseconds: 100,
            deadlineUptimeNanoseconds: 200
        )

        #expect(decision == .bluetoothUnavailable)
    }
}
