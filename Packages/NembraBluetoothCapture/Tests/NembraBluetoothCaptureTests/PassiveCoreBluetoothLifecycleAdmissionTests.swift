import Testing
@testable import NembraBluetoothCapture

struct PassiveCoreBluetoothLifecycleAdmissionTests {
    @Test
    func discoveryRequiresActiveManagerPoweredOnAndActiveScan() {
        #expect(
            PassiveCoreBluetoothDiscoveryAdmissionPolicy.accepts(
                callbackIsFromActiveManager: true,
                isPoweredOn: true,
                isScanning: true
            )
        )

        #expect(
            !PassiveCoreBluetoothDiscoveryAdmissionPolicy.accepts(
                callbackIsFromActiveManager: false,
                isPoweredOn: true,
                isScanning: true
            )
        )
        #expect(
            !PassiveCoreBluetoothDiscoveryAdmissionPolicy.accepts(
                callbackIsFromActiveManager: true,
                isPoweredOn: false,
                isScanning: true
            )
        )
        #expect(
            !PassiveCoreBluetoothDiscoveryAdmissionPolicy.accepts(
                callbackIsFromActiveManager: true,
                isPoweredOn: true,
                isScanning: false
            )
        )
    }

    @Test
    func onlyExplicitCancellationOwnsCancellationRequestBoundary() {
        #expect(
            PassiveCoreBluetoothCancellationBoundary.recordCancellationRequest
                .shouldRecordCancellationRequest
        )
        #expect(
            !PassiveCoreBluetoothCancellationBoundary.interruptionAlreadyRecorded
                .shouldRecordCancellationRequest
        )
    }
}
