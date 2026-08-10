import Testing
@testable import NembraCore

@Suite("Physical capture transport evidence")
struct PhysicalCaptureTransportEvidenceTests {
    @Test("C7D09A22 preserves exact verified Tuya FD50 transport facts")
    func c7d09a22PreservesTransportFacts() {
        let evidence = PhysicalCaptureTransportEvidence.c7d09a22

        #expect(evidence.provenance == .physicalCapture)
        #expect(evidence.captureID == "C7D09A22-96DA-4E46-9BEF-E36F670ADB0E")
        #expect(evidence.observedPeripheralID == "6815A5F5-4D1E-E004-BAE8-6DF924123907")
        #expect(evidence.advertisedLocalName == "demo")
        #expect(evidence.serviceUUID == "FD50")
        #expect(evidence.writeCharacteristicUUID == "00000001-0000-1001-8001-00805F9B07D0")
        #expect(evidence.notifyCharacteristicUUID == "00000002-0000-1001-8001-00805F9B07D0")
        #expect(evidence.completedScenarioCount == 17)
        #expect(evidence.peripheralInitiatedDisconnectCount == 15)
        #expect(abs(evidence.meanConnectedIntervalSeconds - 29.930) < 0.001)
    }

    @Test("transport-only capture cannot mint telemetry semantics")
    func transportOnlyCaptureCannotMintTelemetry() {
        let evidence = PhysicalCaptureTransportEvidence.c7d09a22

        #expect(evidence.characteristicValueEventCount == 0)
        #expect(evidence.authorizesTelemetrySemantics == false)
        #expect(evidence.isStablePhysicalDeviceIdentity == false)
    }
}
