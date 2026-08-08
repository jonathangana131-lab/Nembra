import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One software export provenance")
struct PassiveBluetoothExperimentOneSoftwareExportTests {
    private typealias Codec = PassiveBluetoothExperimentOneSoftwareExportCodec
    private typealias ExportError = PassiveBluetoothExperimentOneSoftwareExportError

    private let scooter = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let neighbor = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let buildInstance = "12345678-90ab-cdef-1234-567890abcdef"
    private let commit = "0123456789abcdef0123456789abcdef01234567"
    private let windowDuration: UInt64 = 10_000_000_000

    @Test("round trip preserves exact bytes, producer authority, declared setup, target, and build rendezvous")
    func roundTripPreservesBoundEvidence() throws {
        let captureJSON = try makeCaptureJSON()
        let result = try makePowerCycleResult()
        let identity = try makeBuildIdentity()
        let declaredSetup = setup()

        let export = try Codec.make(
            captureJSON: captureJSON,
            powerCycleResult: result,
            runtimeBuildIdentity: identity,
            setup: declaredSetup
        )
        let encoded = try Codec.encode(export)
        let verified = try Codec.decodeAndVerify(encoded)

        #expect(verified == export)
        #expect(verified.captureJSON == captureJSON)
        #expect(verified.experimentRecipeID == .es80FingerprintV1)
        #expect(Set(verified.correlationWindows.map(\.observationSeriesIdentity)).count == 1)
        #expect(
            verified.correlationWindows.map(\.observationSeriesIdentity) ==
            result.observationSnapshots.map { $0.observationSeriesIdentity.rawValue }
        )
        #expect(verified.build.buildInstanceID == buildInstance)
        #expect(verified.build.sourceCommitSHA == commit)

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: verified.stationaryManifestJSON,
            captureJSON: verified.captureJSON
        )
        #expect(manifest.schemaVersion == 3)
        #expect(manifest.experimentRecipeID == .es80FingerprintV1)
        #expect(manifest.nembraBuildInstanceID == buildInstance)
        #expect(manifest.nembraBuildCommitSHA == commit)
        #expect(manifest.sourceArtifact.selectedPeripheralIdentifier == scooter.uuidString)
        #expect(manifest.setup == declaredSetup)
    }

    @Test("wire replay cannot mint one authority over catalogs from different producer lives")
    func mixedObservationAuthorityFailsClosed() throws {
        var root = try exportJSONObject()
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        windows[1]["observationSeriesIdentity"] = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        root["correlationWindows"] = windows

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: ExportError.correlationEvidenceInvalid) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("closed-world envelope rejects nested unknown authority claims")
    func nestedUnknownFieldFailsClosed() throws {
        var root = try exportJSONObject()
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        var candidates = try #require(windows[1]["candidates"] as? [[String: Any]])
        candidates[0]["physicallyVerified"] = true
        windows[1]["candidates"] = candidates
        root["correlationWindows"] = windows

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(
            throws: ExportError.unexpectedWireField(
                "correlationWindows[1].candidates[0].physicallyVerified"
            )
        ) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("build metadata cannot diverge from stationary manifest binding")
    func detachedBuildMetadataFailsClosed() throws {
        var root = try exportJSONObject()
        var build = try #require(root["build"] as? [String: Any])
        build["sourceCommitSHA"] = "abcdef0123456789abcdef0123456789abcdef01"
        root["build"] = build

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: ExportError.manifestBuildMismatch) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("exact capture bytes remain bound even when tampering preserves valid JSON")
    func captureByteTamperFailsClosed() throws {
        var root = try exportJSONObject()
        let originalBase64 = try #require(root["captureJSONBase64"] as? String)
        var capture = try #require(Data(base64Encoded: originalBase64))
        capture.append(0x0A)
        root["captureJSONBase64"] = capture.base64EncodedString()

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(
            throws: PassiveBluetoothStationaryCaptureManifestError.manifestDoesNotMatchCapture
        ) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("construction rejects detached correlation summary even when catalogs remain valid")
    func detachedCorrelationSummaryFailsClosed() throws {
        let valid = try makePowerCycleResult()
        var alteredSnapshots = valid.observationSnapshots
        alteredSnapshots[1] = try PassiveBluetoothCandidateObservationSnapshot(
            observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity(),
            windowSequence: alteredSnapshots[1].windowSequence,
            candidates: alteredSnapshots[1].candidates
        )
        let detached = PassiveBluetoothPowerCycleObservationResult(
            windows: valid.windows,
            observationSnapshots: alteredSnapshots,
            correlation: valid.correlation
        )

        #expect(throws: ExportError.correlationEvidenceInvalid) {
            _ = try Codec.make(
                captureJSON: makeCaptureJSON(),
                powerCycleResult: detached,
                runtimeBuildIdentity: makeBuildIdentity(),
                setup: setup()
            )
        }
    }

    @Test("wire cannot shorten an accepted ten-second receipt window")
    func shortenedReceiptWindowFailsClosed() throws {
        var root = try exportJSONObject()
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        let start = try uint64(windows[0]["startedAtUptimeNanoseconds"])
        windows[0]["endedAtUptimeNanoseconds"] = NSNumber(value: start + windowDuration - 1)
        root["correlationWindows"] = windows

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: ExportError.correlationWindowTooShort(index: 0)) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("wire cannot overlap otherwise valid receipt windows")
    func overlappingReceiptWindowsFailClosed() throws {
        var root = try exportJSONObject()
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        let firstEnd = try uint64(windows[0]["endedAtUptimeNanoseconds"])
        let overlappingStart = firstEnd - 1
        windows[1]["startedAtUptimeNanoseconds"] = NSNumber(value: overlappingStart)
        windows[1]["endedAtUptimeNanoseconds"] = NSNumber(value: overlappingStart + windowDuration)
        root["correlationWindows"] = windows

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: ExportError.correlationWindowOverlap(index: 1)) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    @Test("construction rejects receipt chronology below the sealed recipe minimum")
    func constructionRejectsShortReceiptEvidence() throws {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(minimumWindowDurationNanoseconds: 1)
        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 0,
            endedAtUptimeNanoseconds: 1,
            candidates: [candidate(neighbor)]
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: 2,
            endedAtUptimeNanoseconds: 3,
            candidates: [candidate(neighbor), candidate(scooter)]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: 4,
            endedAtUptimeNanoseconds: 5,
            candidates: [candidate(neighbor)]
        )
        let short = try #require(ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 6,
            endedAtUptimeNanoseconds: 7,
            candidates: [candidate(neighbor), candidate(scooter)]
        ))

        #expect(throws: ExportError.correlationWindowTooShort(index: 0)) {
            _ = try Codec.make(
                captureJSON: makeCaptureJSON(),
                powerCycleResult: short,
                runtimeBuildIdentity: makeBuildIdentity(),
                setup: setup()
            )
        }
    }

    private func exportJSONObject() throws -> [String: Any] {
        let export = try Codec.make(
            captureJSON: makeCaptureJSON(),
            powerCycleResult: makePowerCycleResult(),
            runtimeBuildIdentity: makeBuildIdentity(),
            setup: setup()
        )
        return try #require(
            JSONSerialization.jsonObject(with: Codec.encode(export)) as? [String: Any]
        )
    }

    private func setup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }

    private func makeBuildIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-F1",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstance,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    commit
            ],
            executableData: Data("fixture executable".utf8)
        )
    }

    private func makePowerCycleResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: windowDuration
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 0,
            endedAtUptimeNanoseconds: 10_000_000_000,
            candidates: [candidate(neighbor)]
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: 20_000_000_000,
            endedAtUptimeNanoseconds: 30_000_000_000,
            candidates: [candidate(neighbor), candidate(scooter)]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: 40_000_000_000,
            endedAtUptimeNanoseconds: 50_000_000_000,
            candidates: [candidate(neighbor)]
        )
        return try #require(ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 60_000_000_000,
            endedAtUptimeNanoseconds: 70_000_000_000,
            candidates: [candidate(neighbor), candidate(scooter)]
        ))
    }

    private func candidate(_ id: UUID) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
        .init(id: id, isConnectable: true)
    }

    private func uint64(_ value: Any?) throws -> UInt64 {
        try #require(value as? NSNumber).uint64Value
    }

    private func makeCaptureJSON() throws -> Data {
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
            vehicleIdentity: VehicleIdentity(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "AOVOPRO ES80",
                protocolFamily: "unverified-tuya"
            ),
            startedAt: startedAt
        )
        try session.append(
            .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: scooter.uuidString,
                serviceUUID: "FFE0",
                isPrimary: true
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: startedAt
        )
        try session.append(
            .characteristic(try PassiveBluetoothCharacteristicObservation(
                peripheralIdentifier: scooter.uuidString,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                properties: [.notify]
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: startedAt.addingTimeInterval(1)
        )
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: scooter.uuidString,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                origin: .subscriptionUpdate,
                payload: Data([0x01, 0x02])
            )),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3,
            receivedAtDate: startedAt.addingTimeInterval(2)
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}