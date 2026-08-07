import CryptoKit
import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothStationaryCaptureManifestTests {
    private let target = "11111111-2222-3333-4444-555555555555"
    private let other = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
    private let preparedAt = Date(timeIntervalSince1970: 1_750_000_100)
    private let commit = "ABCDEF0123456789ABCDEF0123456789ABCDEF01"

    @Test
    func manifestBindsExactCaptureBytesAndDerivedStationaryFacts() throws {
        let captureJSON = try makeCapture(includeDisconnect: true)
        let setup = PassiveBluetoothStationaryCaptureSetup(
            chargerState: .disconnected,
            stockAppReferenceSetup: .sameDeviceBeforeCapture
        )

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            preparedAt: preparedAt,
            nembraBuildCommitSHA: commit,
            selectedPeripheralIdentifier: target.lowercased(),
            setup: setup
        )

        #expect(manifest.schemaVersion == 1)
        #expect(manifest.experimentKind == .stationaryBaseline)
        #expect(manifest.nembraBuildCommitSHA == commit.lowercased())
        #expect(manifest.sourceArtifact.captureSessionID == sessionID)
        #expect(manifest.sourceArtifact.selectedPeripheralIdentifier == target)
        #expect(manifest.sourceArtifact.byteCount == captureJSON.count)
        #expect(manifest.sourceArtifact.sha256 == SHA256.hash(data: captureJSON).map { String(format: "%02x", $0) }.joined())
        #expect(manifest.setup == setup)
        #expect(manifest.evidenceSummary.targetGATTRecordCount == 3)
        #expect(manifest.evidenceSummary.targetValueRecordCount == 1)
        #expect(manifest.evidenceSummary.stockAppMarkerCount == 1)
        #expect(manifest.evidenceSummary.continuityBreakCount == 1)

        let encoded = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest)
        let verified = try PassiveBluetoothStationaryCaptureManifestJSON.verify(
            manifestJSON: encoded,
            captureJSON: captureJSON
        )
        #expect(verified == manifest)
    }

    @Test
    func trailingWhitespaceChangesExactArtifactAndFailsVerification() throws {
        let captureJSON = try makeCapture()
        let manifest = try makeManifest(captureJSON: captureJSON)
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest)
        var changedBytes = captureJSON
        changedBytes.append(contentsOf: Data("\n".utf8))

        #expect(throws: PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verify(
                manifestJSON: manifestJSON,
                captureJSON: changedBytes
            )
        }
    }

    @Test
    func advertisementOnlyCandidateCannotSatisfySelectedTargetGate() throws {
        let identity = vehicleIdentity()
        var session = try PassiveBluetoothCaptureSession(
            id: sessionID,
            vehicleIdentity: identity,
            startedAt: startedAt
        )
        try session.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(peripheralIdentifier: target)),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: startedAt
        )
        let captureJSON = try PassiveBluetoothCaptureJSON.encode(session)

        #expect(throws: PassiveBluetoothStationaryCaptureManifestError.noTargetGATTEvidence) {
            _ = try makeManifest(captureJSON: captureJSON)
        }
    }

    @Test
    func selectedTargetMustMatchTheOnlyGATTPeripheral() throws {
        let captureJSON = try makeCapture(targetPeripheral: other)
        let canonicalOther = UUID(uuidString: other)!.uuidString

        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError.selectedPeripheralNotPresent(
                requested: target,
                available: [canonicalOther]
            )
        ) {
            _ = try makeManifest(captureJSON: captureJSON)
        }
    }

    @Test
    func mixedGATTPeripheralsFailClosedInsteadOfLabelingACombinedArtifact() throws {
        let captureJSON = try makeCapture(additionalGATTPeripheral: other)
        let available = [target, UUID(uuidString: other)!.uuidString].sorted()

        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError.ambiguousTargetGATTEvidence(available)
        ) {
            _ = try makeManifest(captureJSON: captureJSON)
        }
    }

    @Test
    func unrelatedConnectionOnlyNoiseDoesNotChangeTargetAttributionOrContinuity() throws {
        let captureJSON = try makeCapture(unrelatedConnectionPeripheral: "legacy-nearby-id")
        let manifest = try makeManifest(captureJSON: captureJSON)

        #expect(manifest.sourceArtifact.selectedPeripheralIdentifier == target)
        #expect(manifest.evidenceSummary.targetGATTRecordCount == 3)
        #expect(manifest.evidenceSummary.continuityBreakCount == 0)
    }

    @Test
    func invalidBuildCommitIsRejectedBeforeSidecarCreation() throws {
        let captureJSON = try makeCapture()
        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError.invalidBuildCommitSHA("main")
        ) {
            _ = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
                captureJSON: captureJSON,
                preparedAt: preparedAt,
                nembraBuildCommitSHA: "main",
                selectedPeripheralIdentifier: target,
                setup: .init(chargerState: .disconnected, stockAppReferenceSetup: .none)
            )
        }
    }

    @Test
    func unsupportedManifestSchemaFailsBeforeAnyImportedClaimIsAccepted() throws {
        let captureJSON = try makeCapture()
        let manifest = try makeManifest(captureJSON: captureJSON)
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest)
        var object = try #require(JSONSerialization.jsonObject(with: manifestJSON) as? [String: Any])
        object["schemaVersion"] = 99
        let changedManifestJSON = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothStationaryCaptureManifestError.unsupportedSchemaVersion(99)) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verify(
                manifestJSON: changedManifestJSON,
                captureJSON: captureJSON
            )
        }
    }

    private func makeManifest(captureJSON: Data) throws -> PassiveBluetoothStationaryCaptureManifest {
        try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            preparedAt: preparedAt,
            nembraBuildCommitSHA: commit,
            selectedPeripheralIdentifier: target,
            setup: .init(chargerState: .disconnected, stockAppReferenceSetup: .none)
        )
    }

    private func makeCapture(
        targetPeripheral: String? = nil,
        additionalGATTPeripheral: String? = nil,
        unrelatedConnectionPeripheral: String? = nil,
        includeDisconnect: Bool = false
    ) throws -> Data {
        let selected = targetPeripheral ?? target
        var session = try PassiveBluetoothCaptureSession(
            id: sessionID,
            vehicleIdentity: vehicleIdentity(),
            startedAt: startedAt
        )
        var sequence: UInt64 = 1
        var uptime: UInt64 = 1

        func append(_ event: PassiveBluetoothCaptureEvent) throws {
            try session.append(
                event,
                sequenceNumber: sequence,
                receivedAtUptimeNanoseconds: uptime,
                receivedAtDate: startedAt.addingTimeInterval(Double(sequence))
            )
            sequence += 1
            uptime += 1
        }

        try append(.advertisement(try PassiveBluetoothAdvertisementObservation(peripheralIdentifier: other)))
        try append(.service(try PassiveBluetoothServiceObservation(
            peripheralIdentifier: selected,
            serviceUUID: "FFE0",
            isPrimary: true
        )))
        try append(.characteristic(try PassiveBluetoothCharacteristicObservation(
            peripheralIdentifier: selected,
            serviceUUID: "FFE0",
            characteristicUUID: "FFE1",
            properties: [.notify]
        )))
        try append(.value(try PassiveBluetoothValueObservation(
            peripheralIdentifier: selected,
            serviceUUID: "FFE0",
            characteristicUUID: "FFE1",
            origin: .subscriptionUpdate,
            payload: Data([0x01, 0x02])
        )))
        try append(.stockAppState(try PassiveBluetoothStockAppObservation(
            field: "battery",
            displayedValue: "73%"
        )))

        if let additionalGATTPeripheral {
            try append(.service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: additionalGATTPeripheral,
                serviceUUID: "A201",
                isPrimary: true
            )))
        }

        if let unrelatedConnectionPeripheral {
            try append(.connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: unrelatedConnectionPeripheral,
                state: .disconnected
            )))
        }

        if includeDisconnect {
            try append(.connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: selected,
                state: .disconnected
            )))
        }

        return try PassiveBluetoothCaptureJSON.encode(session)
    }

    private func vehicleIdentity() -> VehicleIdentity {
        VehicleIdentity(
            manufacturer: "AOVOPRO",
            model: "ES80",
            displayName: "AOVOPRO ES80",
            protocolFamily: "unverified-tuya"
        )
    }
}
