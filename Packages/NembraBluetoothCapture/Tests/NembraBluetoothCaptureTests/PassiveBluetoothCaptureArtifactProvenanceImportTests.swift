import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth capture provenance import")
struct PassiveBluetoothCaptureArtifactProvenanceImportTests {
    @Test("byte-bound imported sidecar cannot substitute a different selected target")
    func importedTargetIsRevalidatedAgainstRawEvidence() throws {
        let identity = VehicleIdentity(
            manufacturer: "AOVOPRO",
            model: "ES80",
            displayName: "AOVOPRO ES80",
            protocolFamily: "unknown-2025-es80"
        )
        let target = "11111111-2222-3333-4444-ABCDEFABCDEF"
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: target,
                state: .connected
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1_000,
            receivedAtDate: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let captureJSON = try PassiveBluetoothCaptureJSON.encode(session)
        let original = try PassiveBluetoothCaptureArtifactProvenanceBuilder.make(
            captureJSON: captureJSON,
            nembraSourceRevision: "ae0f2a20a6aecec02d972b9a66f75864d97796e9",
            selectedPeripheralIdentifier: target,
            physicalCorrelationNote: "physical power-cycle correlation",
            researchSetupNote: "stationary, charger disconnected",
            createdAt: Date(timeIntervalSince1970: 1_700_000_500)
        )

        var object = try JSONSerialization.jsonObject(
            with: original.jsonData(prettyPrinted: false)
        ) as! [String: Any]
        var selectedTarget = object["selectedTarget"] as! [String: Any]
        selectedTarget["peripheralIdentifier"] = "99999999-8888-7777-6666-ABCDEFABCDEF"
        object["selectedTarget"] = selectedTarget
        let substitutedJSON = try JSONSerialization.data(withJSONObject: object)
        let substituted = try PassiveBluetoothCaptureArtifactProvenance.decodeJSON(substitutedJSON)

        #expect(!(try substituted.matchesSourceArtifact(captureJSON)))
        #expect(try original.matchesSourceArtifact(captureJSON))
    }
}
