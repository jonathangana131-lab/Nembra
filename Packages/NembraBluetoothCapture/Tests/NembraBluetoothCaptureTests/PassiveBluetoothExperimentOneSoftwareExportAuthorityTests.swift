import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneSoftwareExportAuthorityTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let background = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let foreignAuthority = UUID(uuidString: "99999999-8888-4777-A666-555555555555")!
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let buildIdentifier = "Capture Build V14-authority-tests"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"

    @Test
    func roundTripPreservesOriginalObservationSeriesAuthority() throws {
        let result = try makePowerCycleResult(windowDurationNanoseconds: canonicalDuration)
        let encoded = try makeEncodedExport(result: result)

        let verified = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(encoded)
        let expectedAuthority = try #require(result.observationSnapshots.first)
            .observationSeriesIdentity.rawValue

        #expect(verified.correlationWindows.count == 4)
        #expect(verified.correlationWindows.allSatisfy {
            $0.observationSeriesIdentity == expectedAuthority
        })
    }

    @Test
    func decodeRejectsCrossProducerWindowSplicingInsteadOfMintingFreshAuthority() throws {
        let result = try makePowerCycleResult(windowDurationNanoseconds: canonicalDuration)
        let encoded = try makeEncodedExport(result: result)
        var root = try rootObject(encoded)
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        windows[2]["observationSeriesIdentity"] = foreignAuthority.uuidString
        root["correlationWindows"] = windows

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(tampered)
        }
    }

    @Test
    func makeRejectsPowerCycleResultBelowCanonicalExperimentOneDuration() throws {
        let observed = canonicalDuration - 1
        let result = try makePowerCycleResult(windowDurationNanoseconds: observed)

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .correlationWindowDurationRejected(
                    index: 0,
                    observedNanoseconds: observed,
                    minimumRequiredNanoseconds: canonicalDuration
                )
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
                captureJSON: makeCapture(),
                powerCycleResult: result,
                runtimeBuildIdentity: makeRuntimeIdentity()
            )
        }
    }

    @Test
    func decodeRejectsSerializedDurationShrinkageBelowCanonicalPolicy() throws {
        let result = try makePowerCycleResult(windowDurationNanoseconds: canonicalDuration)
        let encoded = try makeEncodedExport(result: result)
        var root = try rootObject(encoded)
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        let started = try #require(windows[1]["startedAtUptimeNanoseconds"] as? NSNumber)
            .uint64Value
        let observed = canonicalDuration - 1
        windows[1]["endedAtUptimeNanoseconds"] = NSNumber(value: started + observed)
        root["correlationWindows"] = windows

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .correlationWindowDurationRejected(
                    index: 1,
                    observedNanoseconds: observed,
                    minimumRequiredNanoseconds: canonicalDuration
                )
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(tampered)
        }
    }

    @Test
    func decodeRejectsNestedAuthorityFieldSmuggling() throws {
        let result = try makePowerCycleResult(windowDurationNanoseconds: canonicalDuration)
        let encoded = try makeEncodedExport(result: result)
        var root = try rootObject(encoded)
        var build = try #require(root["build"] as? [String: Any])
        build["physicalGO"] = true
        root["build"] = build

        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .unexpectedWireField("build.physicalGO")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(tampered)
        }
    }

    private var canonicalDuration: UInt64 {
        PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
    }

    private func makeEncodedExport(
        result: PassiveBluetoothPowerCycleObservationResult
    ) throws -> Data {
        let softwareExport = try PassiveBluetoothExperimentOneSoftwareExportCodec.make(
            captureJSON: makeCapture(),
            powerCycleResult: result,
            runtimeBuildIdentity: makeRuntimeIdentity()
        )
        return try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(
            softwareExport,
            prettyPrinted: false
        )
    }

    private func makeRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    sourceCommitSHA,
            ],
            executableData: Data("software-export-authority-tests".utf8)
        )
    }

    private func makePowerCycleResult(
        windowDurationNanoseconds duration: UInt64
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 1
        )
        let backgroundCandidate = PassiveBluetoothCandidateObservationSnapshot.Candidate(
            id: background,
            isConnectable: true
        )
        let targetCandidate = PassiveBluetoothCandidateObservationSnapshot.Candidate(
            id: target,
            isConnectable: true
        )
        let stride = canonicalDuration + 1_000_000_000

        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 0,
            endedAtUptimeNanoseconds: duration,
            candidates: [backgroundCandidate]
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: stride,
            endedAtUptimeNanoseconds: stride + duration,
            candidates: [backgroundCandidate, targetCandidate]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: stride * 2,
            endedAtUptimeNanoseconds: stride * 2 + duration,
            candidates: [backgroundCandidate]
        )
        let result = try ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: stride * 3,
            endedAtUptimeNanoseconds: stride * 3 + duration,
            candidates: [backgroundCandidate, targetCandidate]
        )
        return try #require(result)
    }

    private func makeCapture() throws -> Data {
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
                payload: Data([0x01, 0x02])
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: Date(timeIntervalSince1970: 1_750_000_002)
        )
        return try PassiveBluetoothCaptureJSON.encode(session)
    }

    private func rootObject(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
