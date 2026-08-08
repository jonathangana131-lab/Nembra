import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneSoftwareExportTruthTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let alternateTarget = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
    private let noise = UUID(uuidString: "99999999-8888-4777-8666-555555555555")!
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let seriesID = UUID(uuidString: "12345678-1234-4ABC-8DEF-123456789ABC")!
    private let commit = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildIdentifier = "Capture Build V14-software-export"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"

    @Test
    func explicitSetupDeclarationIsPreservedInsteadOfFabricatedByTheExporter() throws {
        let captureJSON = try makeCapture(payload: Data([0x01, 0x02]))
        let setup = PassiveBluetoothStationaryCaptureSetup(
            chargerState: .connected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
        let export = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
            captureJSON: captureJSON,
            powerCycleResult: makePowerCycleResult(target: target),
            runtimeBuildIdentity: makeRuntimeBuildIdentity(),
            setup: setup
        )
        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: export.stationaryManifestJSON,
            captureJSON: captureJSON
        )

        #expect(manifest.setup == setup)
        #expect(manifest.sourceArtifact.selectedPeripheralIdentifier == target.uuidString)
        #expect(manifest.experimentRecipeID == .es80FingerprintV1)
        #expect(manifest.nembraBuildInstanceID == buildInstanceID)
    }

    @Test
    func roundTripRetainsReplayableCorrelationAndBuildRendezvous() throws {
        let export = try makeExport()
        let encoded = try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(export)
        let verified = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(encoded)

        #expect(verified == export)
        #expect(verified.correlationWindows.count == 4)
        #expect(verified.correlationWindows.map(\.observationSeriesIdentity) == Array(repeating: seriesID, count: 4))
        #expect(verified.build.buildIdentifier == buildIdentifier)
        #expect(verified.build.buildInstanceID == buildInstanceID)
        #expect(verified.build.sourceCommitSHA == commit)
        #expect(verified.build.executableSHA256.count == 64)
    }

    @Test
    func verifierRejectsShortenedReceiptWindowEvenWhenCorrelationCatalogsAreUnchanged() throws {
        let encoded = try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(makeExport())
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        let start = try #require(windows[0]["startedAtUptimeNanoseconds"] as? NSNumber).uint64Value
        windows[0]["endedAtUptimeNanoseconds"] = NSNumber(value: start + 9_999_999_999)
        root["correlationWindows"] = windows
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError.correlationWindowTooShort(index: 0)
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(tampered)
        }
    }

    @Test
    func verifierRejectsOverlappingReceiptWindowsEvenWhenSequencesRemainIncreasing() throws {
        let encoded = try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(makeExport())
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        let firstEnd = try #require(windows[0]["endedAtUptimeNanoseconds"] as? NSNumber).uint64Value
        let overlappingStart = firstEnd - 1
        windows[1]["startedAtUptimeNanoseconds"] = NSNumber(value: overlappingStart)
        windows[1]["endedAtUptimeNanoseconds"] = NSNumber(value: overlappingStart + 10_000_000_000)
        root["correlationWindows"] = windows
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError.correlationWindowOverlap(index: 1)
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(tampered)
        }
    }

    @Test
    func changedCorrelationTargetCannotReuseOriginalCaptureManifest() throws {
        let encoded = try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(makeExport())
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])

        for index in [1, 3] {
            var candidates = try #require(windows[index]["candidates"] as? [[String: Any]])
            let targetIndex = try #require(candidates.firstIndex(where: {
                ($0["peripheralIdentifier"] as? String) == target.uuidString
            }))
            candidates[targetIndex]["peripheralIdentifier"] = alternateTarget.uuidString
            windows[index]["candidates"] = candidates
        }
        root["correlationWindows"] = windows
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError.manifestTargetMismatch
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(tampered)
        }
    }

    @Test
    func selfDeclaredPhysicalAuthorizationCannotBeSmuggledIntoClosedWorldWire() throws {
        let encoded = try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(makeExport())
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        root["fieldAuthorized"] = true
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .unexpectedWireField("fieldAuthorized")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(tampered)
        }
    }

    @Test
    func detachedCorrelationSummaryCannotOverrideReplayedRawCatalogs() throws {
        let captureJSON = try makeCapture(payload: Data([0x01]))
        let valid = try makePowerCycleResult(target: target)
        let different = try makePowerCycleResult(target: alternateTarget)
        let forged = PassiveBluetoothPowerCycleObservationResult(
            windows: valid.windows,
            observationSnapshots: valid.observationSnapshots,
            correlation: different.correlation
        )

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
                captureJSON: captureJSON,
                powerCycleResult: forged,
                runtimeBuildIdentity: makeRuntimeBuildIdentity(),
                setup: defaultSetup()
            )
        }
    }

    private func makeExport() throws -> PassiveBluetoothExperimentOneSoftwareExport {
        try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
            captureJSON: makeCapture(payload: Data([0x01, 0x02])),
            powerCycleResult: makePowerCycleResult(target: target),
            runtimeBuildIdentity: makeRuntimeBuildIdentity(),
            setup: defaultSetup()
        )
    }

    private func makeRuntimeBuildIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey: buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey: commit,
            ],
            executableData: Data("software-export-fixture".utf8)
        )
    }

    private func defaultSetup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }

    private func makePowerCycleResult(target: UUID) throws -> PassiveBluetoothPowerCycleObservationResult {
        let authority = PassiveBluetoothCandidateObservationSeriesIdentity(rawValue: seriesID)
        let candidateSets: [[PassiveBluetoothCandidateObservationSnapshot.Candidate]] = [
            [.init(id: noise, isConnectable: true)],
            [.init(id: noise, isConnectable: true), .init(id: target, isConnectable: true)],
            [.init(id: noise, isConnectable: true)],
            [.init(id: noise, isConnectable: true), .init(id: target, isConnectable: true)],
        ]

        var snapshots: [PassiveBluetoothCandidateObservationSnapshot] = []
        var windows: [PassiveBluetoothPowerCycleObservationWindowReceipt] = []
        for index in PassiveBluetoothPowerCycleObservationPhase.allCases.indices {
            let sequence = PassiveBluetoothCandidateObservationWindowSequence(rawValue: UInt64(index + 1))
            let snapshot = try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: authority,
                windowSequence: sequence,
                candidates: candidateSets[index]
            )
            let start = UInt64(index) * 20_000_000_000
            snapshots.append(snapshot)
            windows.append(
                PassiveBluetoothPowerCycleObservationWindowReceipt(
                    phase: PassiveBluetoothPowerCycleObservationPhase.allCases[index],
                    windowSequence: sequence,
                    startedAtUptimeNanoseconds: start,
                    endedAtUptimeNanoseconds: start + 10_000_000_000,
                    observedCandidateCount: snapshot.candidates.count
                )
            )
        }

        let correlation = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: snapshots[0],
            firstOn: snapshots[1],
            secondOff: snapshots[2],
            secondOn: snapshots[3]
        )
        return PassiveBluetoothPowerCycleObservationResult(
            windows: windows,
            observationSnapshots: snapshots,
            correlation: correlation
        )
    }

    private func makeCapture(payload: Data) throws -> Data {
        var session = try PassiveBluetoothCaptureSession(
            id: sessionID,
            vehicleIdentity: .init(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "AOVOPRO ES80",
                protocolFamily: "unverified-tuya"
            ),
            startedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        try session.append(
            .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: target.uuidString,
                serviceUUID: "FFE0",
                isPrimary: true
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: Date(timeIntervalSince1970: 1_750_000_001)
        )
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: target.uuidString,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                origin: .subscriptionUpdate,
                payload: payload
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: Date(timeIntervalSince1970: 1_750_000_002)
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}