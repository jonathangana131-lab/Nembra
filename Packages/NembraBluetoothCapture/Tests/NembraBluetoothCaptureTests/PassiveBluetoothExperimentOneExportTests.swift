import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One final export envelope")
struct PassiveBluetoothExperimentOneExportTests {
    private let es80 = VehicleProfile.aovoproES80.identity
    private let target = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let neighbor = UUID(uuidString: "90000000-0000-0000-0000-000000000009")!
    private let series = UUID(uuidString: "70000000-0000-0000-0000-000000000007")!
    private let sessionID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    private let preparedAt = Date(timeIntervalSince1970: 5_500)
    private let buildIdentifier = "NembraCapture-V14-F1"
    private let buildInstanceID = "11111111-2222-3333-4444-555555555555"
    private let sourceCommitSHA = "0123456789abcdef0123456789abcdef01234567"
    private let executableSHA256 = String(repeating: "a", count: 64)

    @Test("valid envelope preserves exact sealed bytes and remains physically unauthorized")
    func validEnvelopeRoundTrips() throws {
        let captureJSON = try makeCaptureJSON()
        let exportJSON = try makeEnvelope(captureJSON: captureJSON)

        let verified = try PassiveBluetoothExperimentOneExport.verify(exportJSON)

        #expect(verified.sealedCaptureJSON == captureJSON)
        #expect(verified.manifest.schemaVersion == 3)
        #expect(verified.manifest.experimentID == sessionID)
        #expect(verified.experimentRecipeID == .es80FingerprintV1)
        #expect(verified.correlatedPeripheralIdentifier == target)
        #expect(verified.runtimeBuildIdentity.buildIdentifier == buildIdentifier)
        #expect(verified.runtimeBuildIdentity.buildInstanceID == buildInstanceID)
        #expect(verified.runtimeBuildIdentity.sourceCommitSHA == sourceCommitSHA)
        #expect(verified.runtimeBuildIdentity.executableSHA256 == executableSHA256)
        #expect(verified.fieldAuthorization == .notBound)
        #expect(verified.manifest.setup.chargerState == .disconnected)
        #expect(verified.manifest.setup.executionContext == .foregroundUnlockedScreenOn)
        #expect(verified.manifest.setup.stockAppReferenceSetup == .none)
    }

    @Test("outer schema is closed world")
    func injectedOuterFieldFailsClosed() throws {
        let original = try makeEnvelope(captureJSON: makeCaptureJSON())
        let tampered = try mutateJSON(original) { root in
            root["pretendPhysicalPass"] = true
        }

        #expect(throws: PassiveBluetoothExperimentOneExportError.unexpectedEnvelopeField("pretendPhysicalPass")) {
            try PassiveBluetoothExperimentOneExport.verify(tampered)
        }
    }

    @Test("envelope cannot self-promote field authorization")
    func forgedFieldAuthorizationFailsClosed() throws {
        let original = try makeEnvelope(captureJSON: makeCaptureJSON())
        let tampered = try mutateJSON(original) { root in
            root["fieldAuthorization"] = "accepted"
        }

        #expect(throws: PassiveBluetoothExperimentOneExportError.unsupportedFieldAuthorization("accepted")) {
            try PassiveBluetoothExperimentOneExport.verify(tampered)
        }
    }

    @Test("exact capture-byte substitution cannot survive manifest binding")
    func substitutedCaptureFailsClosed() throws {
        let original = try makeEnvelope(captureJSON: makeCaptureJSON())
        let alteredCapture = try makeCaptureJSON(
            targetServiceUUID: "FFF1"
        )
        let tampered = try mutateJSON(original) { root in
            root["sealedCaptureJSON"] = alteredCapture.base64EncodedString()
        }

        #expect(throws: PassiveBluetoothExperimentOneExportError.manifestBindingInvalid) {
            try PassiveBluetoothExperimentOneExport.verify(tampered)
        }
    }

    @Test("correlation evidence from a second producer life cannot be spliced")
    func mixedObservationAuthorityFailsClosed() throws {
        let original = try makeEnvelope(captureJSON: makeCaptureJSON())
        let foreignSeries = UUID(uuidString: "80000000-0000-0000-0000-000000000008")!
        let tampered = try mutateJSON(original) { root in
            var windows = root["powerCycleWindows"] as! [[String: Any]]
            windows[2]["observationSeriesID"] = foreignSeries.uuidString
            root["powerCycleWindows"] = windows
        }

        #expect(throws: PassiveBluetoothExperimentOneExportError.captureEvidenceNotStructurallyCoherent) {
            try PassiveBluetoothExperimentOneExport.verify(tampered)
        }
    }

    @Test("one nanosecond short Ready-to-Horizon interval remains rejected")
    func shortObservationHorizonFailsClosed() throws {
        let shortCapture = try makeCaptureJSON(
            postReadyDurationNanoseconds:
                PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds - 1
        )
        let exportJSON = try makeEnvelope(captureJSON: shortCapture)

        #expect(throws: PassiveBluetoothExperimentOneExportError.captureEvidenceNotStructurallyCoherent) {
            try PassiveBluetoothExperimentOneExport.verify(exportJSON)
        }
    }

    @Test("power-cycle receipt candidate counts are replayed rather than trusted")
    func detachedReceiptCountFailsClosed() throws {
        let original = try makeEnvelope(captureJSON: makeCaptureJSON())
        let tampered = try mutateJSON(original) { root in
            var windows = root["powerCycleWindows"] as! [[String: Any]]
            windows[1]["observedCandidateCount"] = 999
            root["powerCycleWindows"] = windows
        }

        #expect(throws: PassiveBluetoothExperimentOneExportError.captureEvidenceNotStructurallyCoherent) {
            try PassiveBluetoothExperimentOneExport.verify(tampered)
        }
    }

    private func makeEnvelope(captureJSON: Data) throws -> Data {
        let setup = PassiveBluetoothStationaryCaptureSetup(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentID: sessionID,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            nembraBuildIdentifier: buildIdentifier,
            nembraBuildInstanceID: buildInstanceID,
            nembraBuildCommitSHA: sourceCommitSHA,
            selectedPeripheralIdentifier: target.uuidString,
            setup: setup
        )
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest)

        let envelope = WireEnvelope(
            schemaVersion: 1,
            experimentRecipeID: PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue,
            preparedAt: preparedAt,
            fieldAuthorization: PassiveBluetoothExperimentOneExternalFieldAuthorization.notBound.rawValue,
            correlatedPeripheralIdentifier: target,
            runtimeBuildIdentity: .init(
                buildIdentifier: buildIdentifier,
                buildInstanceID: buildInstanceID,
                sourceCommitSHA: sourceCommitSHA,
                executableSHA256: executableSHA256
            ),
            powerCycleWindows: makePowerCycleWindows(),
            stationaryManifestJSON: manifestJSON,
            sealedCaptureJSON: captureJSON
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    private func makePowerCycleWindows() -> [WireWindow] {
        PassiveBluetoothPowerCycleObservationPhase.allCases.enumerated().map { index, phase in
            let sequence = UInt64(index + 1)
            let start = UInt64(index) * 20_000_000_000
            let candidates: [WireCandidate]
            if phase.operatorExpectedPowerOn {
                candidates = [
                    .init(id: neighbor, isConnectable: true),
                    .init(id: target, isConnectable: true),
                ]
            } else {
                candidates = [.init(id: neighbor, isConnectable: true)]
            }
            return WireWindow(
                phase: phaseName(phase),
                observationSeriesID: series,
                windowSequence: sequence,
                startedAtUptimeNanoseconds: start,
                endedAtUptimeNanoseconds:
                    start + PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds,
                observedCandidateCount: candidates.count,
                candidates: candidates
            )
        }
    }

    private func phaseName(_ phase: PassiveBluetoothPowerCycleObservationPhase) -> String {
        switch phase {
        case .firstPoweredOff: "firstPoweredOff"
        case .firstPoweredOn: "firstPoweredOn"
        case .secondPoweredOff: "secondPoweredOff"
        case .secondPoweredOn: "secondPoweredOn"
        }
    }

    private func makeCaptureJSON(
        targetServiceUUID: String = "FFF0",
        postReadyDurationNanoseconds: UInt64 =
            PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds
    ) throws -> Data {
        let record = PassiveBluetoothCaptureRecord(
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 4_000),
            event: .service(
                try PassiveBluetoothServiceObservation(
                    peripheralIdentifier: target.uuidString,
                    serviceUUID: targetServiceUUID,
                    isPrimary: true
                )
            )
        )
        let readyUptime: UInt64 = 1_000
        let ready = PassiveBluetoothObservationBoundary(
            kind: .finiteAcquisitionReady,
            recordSequenceWatermark: 1,
            observedAtUptimeNanoseconds: readyUptime,
            observedAtDate: Date(timeIntervalSince1970: 5_000)
        )
        let horizon = PassiveBluetoothObservationBoundary(
            kind: .observationHorizon,
            recordSequenceWatermark: 1,
            observedAtUptimeNanoseconds: readyUptime + postReadyDurationNanoseconds,
            observedAtDate: Date(timeIntervalSince1970: 5_060)
        )
        let session = try PassiveBluetoothCaptureSession(
            id: sessionID,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 4_000),
            records: [record],
            observationBoundaries: [ready, horizon]
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }

    private func mutateJSON(
        _ data: Data,
        mutation: (inout [String: Any]) -> Void
    ) throws -> Data {
        var root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutation(&root)
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private struct WireEnvelope: Codable {
        let schemaVersion: Int
        let experimentRecipeID: String
        let preparedAt: Date
        let fieldAuthorization: String
        let correlatedPeripheralIdentifier: UUID
        let runtimeBuildIdentity: WireBuildIdentity
        let powerCycleWindows: [WireWindow]
        let stationaryManifestJSON: Data
        let sealedCaptureJSON: Data
    }

    private struct WireBuildIdentity: Codable {
        let buildIdentifier: String
        let buildInstanceID: String
        let sourceCommitSHA: String
        let executableSHA256: String
    }

    private struct WireWindow: Codable {
        let phase: String
        let observationSeriesID: UUID
        let windowSequence: UInt64
        let startedAtUptimeNanoseconds: UInt64
        let endedAtUptimeNanoseconds: UInt64
        let observedCandidateCount: Int
        let candidates: [WireCandidate]
    }

    private struct WireCandidate: Codable {
        let id: UUID
        let isConnectable: Bool?
    }
}
