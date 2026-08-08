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
    private let buildIdentifier = "Capture Build V14-F1"

    @Test
    func manifestV2BindsExactCaptureBytesRecipeAndBuildIdentity() throws {
        let captureJSON = try makeCapture(includeStockAppMarker: true, includeDisconnect: true)
        let setup = PassiveBluetoothStationaryCaptureSetup(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .sameDeviceBeforeCapture
        )

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: "  \(buildIdentifier)  ",
            nembraBuildCommitSHA: commit,
            selectedPeripheralIdentifier: target.lowercased(),
            setup: setup
        )

        #expect(manifest.schemaVersion == 2)
        #expect(manifest.experimentKind == .stationaryBaseline)
        #expect(manifest.experimentRecipeID == .es80FingerprintV1)
        #expect(manifest.nembraBuildIdentifier == buildIdentifier)
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
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["experimentRecipeID"] as? String == "ES80-FINGERPRINT-v1")
        #expect(object["nembraBuildIdentifier"] as? String == buildIdentifier)
        #expect(object["nembraBuildCommitSHA"] as? String == commit.lowercased())

        let verified = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: encoded,
            captureJSON: captureJSON
        )
        #expect(verified == manifest)
    }

    @Test
    func legacyV1RemainsReadableWithoutInventingV2Provenance() throws {
        let captureJSON = try makeCapture()
        let current = try makeManifest(captureJSON: captureJSON)
        let currentJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(current)
        var object = try #require(JSONSerialization.jsonObject(with: currentJSON) as? [String: Any])
        object["schemaVersion"] = 1
        object.removeValue(forKey: "experimentRecipeID")
        object.removeValue(forKey: "nembraBuildIdentifier")
        let legacyJSON = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        let verified = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: legacyJSON,
            captureJSON: captureJSON
        )
        #expect(verified.schemaVersion == 1)
        #expect(verified.experimentRecipeID == nil)
        #expect(verified.nembraBuildIdentifier == nil)
        #expect(verified.nembraBuildCommitSHA == commit.lowercased())
        #expect(verified.sourceArtifact == current.sourceArtifact)
        #expect(verified.evidenceSummary == current.evidenceSummary)

        let reencoded = try PassiveBluetoothStationaryCaptureManifestJSON.encode(verified)
        let reencodedObject = try #require(JSONSerialization.jsonObject(with: reencoded) as? [String: Any])
        #expect(reencodedObject["schemaVersion"] as? Int == 1)
        #expect(reencodedObject["experimentRecipeID"] == nil)
        #expect(reencodedObject["nembraBuildIdentifier"] == nil)
    }

    @Test
    func schemaV1CannotSmuggleV2RecipeOrBuildIdentity() throws {
        let captureJSON = try makeCapture()
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(
            makeManifest(captureJSON: captureJSON)
        )
        var object = try #require(JSONSerialization.jsonObject(with: manifestJSON) as? [String: Any])
        object["schemaVersion"] = 1
        object.removeValue(forKey: "nembraBuildIdentifier")
        let relabeled = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError
                .unexpectedManifestField("experimentRecipeID")
        ) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: relabeled,
                captureJSON: captureJSON
            )
        }
    }

    @Test
    func schemaV2RequiresBothRecipeAndBuildIdentifier() throws {
        let captureJSON = try makeCapture()
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(
            makeManifest(captureJSON: captureJSON)
        )

        var missingRecipe = try #require(JSONSerialization.jsonObject(with: manifestJSON) as? [String: Any])
        missingRecipe.removeValue(forKey: "experimentRecipeID")
        let missingRecipeJSON = try JSONSerialization.data(withJSONObject: missingRecipe, options: [.sortedKeys])
        #expect(throws: DecodingError.self) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: missingRecipeJSON,
                captureJSON: captureJSON
            )
        }

        var missingBuild = try #require(JSONSerialization.jsonObject(with: manifestJSON) as? [String: Any])
        missingBuild.removeValue(forKey: "nembraBuildIdentifier")
        let missingBuildJSON = try JSONSerialization.data(withJSONObject: missingBuild, options: [.sortedKeys])
        #expect(throws: DecodingError.self) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: missingBuildJSON,
                captureJSON: captureJSON
            )
        }
    }

    @Test
    func unknownRecipeIdentifierFailsClosed() throws {
        let captureJSON = try makeCapture()
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(
            makeManifest(captureJSON: captureJSON)
        )
        var object = try #require(JSONSerialization.jsonObject(with: manifestJSON) as? [String: Any])
        object["experimentRecipeID"] = "ES80-FINGERPRINT-v999"
        let changed = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: DecodingError.self) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: changed,
                captureJSON: captureJSON
            )
        }
    }

    @Test
    func invalidBuildIdentifierFailsBeforeManifestCreation() throws {
        let captureJSON = try makeCapture()
        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError.invalidBuildIdentifier("   ")
        ) {
            _ = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
                captureJSON: captureJSON,
                experimentRecipe: .es80FingerprintV1,
                preparedAt: preparedAt,
                nembraBuildIdentifier: "   ",
                nembraBuildCommitSHA: commit,
                selectedPeripheralIdentifier: target,
                setup: defaultSetup()
            )
        }
    }

    @Test
    func trailingWhitespaceChangesExactArtifactAndFailsVerification() throws {
        let captureJSON = try makeCapture()
        let manifest = try makeManifest(captureJSON: captureJSON)
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest)
        var changedBytes = captureJSON
        changedBytes.append(contentsOf: Data("\n".utf8))

        #expect(throws: PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: manifestJSON,
                captureJSON: changedBytes
            )
        }
    }

    @Test
    func advertisementOnlyCandidateCannotSatisfySelectedTargetGate() throws {
        var session = try PassiveBluetoothCaptureSession(
            id: sessionID,
            vehicleIdentity: vehicleIdentity(),
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
    func mixedGATTPeripheralsFailClosedInsteadOfLabelingCombinedArtifact() throws {
        let captureJSON = try makeCapture(additionalGATTPeripheral: other)
        let available = [target, UUID(uuidString: other)!.uuidString].sorted()

        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError.ambiguousTargetGATTEvidence(available)
        ) {
            _ = try makeManifest(captureJSON: captureJSON)
        }
    }

    @Test
    func unrelatedConnectionNoiseCannotEstablishTargetButDisconnectStillBreaksContinuity() throws {
        let captureJSON = try makeCapture(unrelatedConnectionPeripheral: "legacy-nearby-id")
        let manifest = try makeManifest(captureJSON: captureJSON)

        #expect(manifest.sourceArtifact.selectedPeripheralIdentifier == target)
        #expect(manifest.evidenceSummary.targetGATTRecordCount == 3)
        #expect(manifest.evidenceSummary.continuityBreakCount == 1)
    }

    @Test
    func genericInterruptionUsesCoreContinuityClassification() throws {
        let manifest = try makeManifest(captureJSON: makeCapture(includeInterruption: true))
        #expect(manifest.evidenceSummary.continuityBreakCount == 1)
    }

    @Test
    func stockAppMarkersRequireDeclaredReferenceSetup() throws {
        let captureJSON = try makeCapture(includeStockAppMarker: true)
        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError
                .stockAppMarkersWithoutDeclaredReference(markerCount: 1)
        ) {
            _ = try makeManifest(captureJSON: captureJSON)
        }
    }

    @Test
    func declaredStockAppReferenceRequiresImmutableMarkers() throws {
        let captureJSON = try makeCapture()
        let setup = PassiveBluetoothStationaryCaptureSetup(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .sameDeviceBeforeCapture
        )

        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError
                .stockAppReferenceDeclaredWithoutMarkers
        ) {
            _ = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
                captureJSON: captureJSON,
                experimentRecipe: .es80FingerprintV1,
                preparedAt: preparedAt,
                nembraBuildIdentifier: buildIdentifier,
                nembraBuildCommitSHA: commit,
                selectedPeripheralIdentifier: target,
                setup: setup
            )
        }
    }

    @Test
    func importedDerivedSummaryTamperingIsRejected() throws {
        let captureJSON = try makeCapture()
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(
            makeManifest(captureJSON: captureJSON)
        )
        var object = try #require(JSONSerialization.jsonObject(with: manifestJSON) as? [String: Any])
        var evidenceSummary = try #require(object["evidenceSummary"] as? [String: Any])
        evidenceSummary["targetValueRecordCount"] = 999
        object["evidenceSummary"] = evidenceSummary
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: tampered,
                captureJSON: captureJSON
            )
        }
    }

    @Test
    func invalidBuildCommitIsRejectedBeforeManifestCreation() throws {
        let captureJSON = try makeCapture()
        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError.invalidBuildCommitSHA("main")
        ) {
            _ = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
                captureJSON: captureJSON,
                experimentRecipe: .es80FingerprintV1,
                preparedAt: preparedAt,
                nembraBuildIdentifier: buildIdentifier,
                nembraBuildCommitSHA: "main",
                selectedPeripheralIdentifier: target,
                setup: defaultSetup()
            )
        }
    }

    @Test
    func unsupportedManifestSchemaFailsBeforeImportedClaimAcceptance() throws {
        let captureJSON = try makeCapture()
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(
            makeManifest(captureJSON: captureJSON)
        )
        var object = try #require(JSONSerialization.jsonObject(with: manifestJSON) as? [String: Any])
        object["schemaVersion"] = 99
        let changed = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothStationaryCaptureManifestError.unsupportedSchemaVersion(99)) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: changed,
                captureJSON: captureJSON
            )
        }
    }

    @Test
    func unknownSchemaV2FieldsFailClosedInsteadOfBeingIgnored() throws {
        let captureJSON = try makeCapture()
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(
            makeManifest(captureJSON: captureJSON)
        )

        var topLevel = try #require(JSONSerialization.jsonObject(with: manifestJSON) as? [String: Any])
        topLevel["physicallyVerified"] = true
        let topLevelJSON = try JSONSerialization.data(withJSONObject: topLevel, options: [.sortedKeys])
        #expect(throws: PassiveBluetoothStationaryCaptureManifestError.unexpectedManifestField("physicallyVerified")) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: topLevelJSON,
                captureJSON: captureJSON
            )
        }

        var nested = try #require(JSONSerialization.jsonObject(with: manifestJSON) as? [String: Any])
        var setup = try #require(nested["setup"] as? [String: Any])
        setup["backgroundCaptureAttested"] = true
        nested["setup"] = setup
        let nestedJSON = try JSONSerialization.data(withJSONObject: nested, options: [.sortedKeys])
        #expect(throws: PassiveBluetoothStationaryCaptureManifestError.unexpectedManifestField("setup.backgroundCaptureAttested")) {
            _ = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
                manifestJSON: nestedJSON,
                captureJSON: captureJSON
            )
        }
    }

    private func makeManifest(captureJSON: Data) throws -> PassiveBluetoothStationaryCaptureManifest {
        try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: buildIdentifier,
            nembraBuildCommitSHA: commit,
            selectedPeripheralIdentifier: target,
            setup: defaultSetup()
        )
    }

    private func defaultSetup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }

    private func makeCapture(
        targetPeripheral: String? = nil,
        additionalGATTPeripheral: String? = nil,
        unrelatedConnectionPeripheral: String? = nil,
        includeStockAppMarker: Bool = false,
        includeDisconnect: Bool = false,
        includeInterruption: Bool = false
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
        if includeStockAppMarker {
            try append(.stockAppState(try PassiveBluetoothStockAppObservation(
                field: "battery",
                displayedValue: "73%"
            )))
        }
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
        if includeInterruption {
            try append(.interruption(try PassiveBluetoothCaptureInterruption(
                reason: "foreground evidence integrity lost"
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