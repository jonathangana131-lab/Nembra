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
    func cancellationCausesHaveFixedEvidenceSemantics() {
        #expect(
            PassiveCoreBluetoothCancellationCause.operatorRequest.interruptionReason
                == "connection cancellation requested"
        )
        #expect(
            PassiveCoreBluetoothCancellationCause.foregroundIntegrityLoss.interruptionReason
                == "foreground evidence integrity lost"
        )
        #expect(
            PassiveCoreBluetoothCancellationCause.finalizedArtifactTeardown.interruptionReason == nil
        )
        #expect(
            PassiveCoreBluetoothCancellationCause.interruptionAlreadyRecorded.interruptionReason == nil
        )

        #expect(PassiveCoreBluetoothCancellationCause.operatorRequest.diagnosticMessage != nil)
        #expect(PassiveCoreBluetoothCancellationCause.foregroundIntegrityLoss.diagnosticMessage != nil)
        #expect(PassiveCoreBluetoothCancellationCause.finalizedArtifactTeardown.diagnosticMessage == nil)
        #expect(PassiveCoreBluetoothCancellationCause.interruptionAlreadyRecorded.diagnosticMessage == nil)
    }
}
