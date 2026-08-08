import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One software export duration authority")
struct PassiveBluetoothExperimentOneSoftwareExportDurationPolicyTests {
    private typealias Codec = PassiveBluetoothExperimentOneSoftwareExportCodec

    private let scooter = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let neighbor = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    @Test("construction rejects research windows shorter than ES80-FINGERPRINT-v1 policy")
    func constructionRejectsSubminimumWindows() throws {
        let result = try makePowerCycleResult(windowDurationNanoseconds: 1)
        let duration = PassiveBluetoothPowerCycleObservationWindowDurationAssessment.assess(
            result: result,
            minimumDurationNanoseconds:
                PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
        )
        #expect(duration.status == .insufficientDuration)

        #expect(throws: Error.self) {
            _ = try Codec.make(
                captureJSON: makeCaptureJSON(),
                powerCycleResult: result,
                runtimeBuildIdentity: makeBuildIdentity(),
                setup: setup
            )
        }
    }

    @Test("offline verification rejects a wire artifact that shrinks an accepted window below recipe policy")
    func decoderRejectsSubminimumWindowTamper() throws {
        let validResult = try makePowerCycleResult(
            windowDurationNanoseconds:
                PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
        )
        let export = try Codec.make(
            captureJSON: makeCaptureJSON(),
            powerCycleResult: validResult,
            runtimeBuildIdentity: makeBuildIdentity(),
            setup: setup
        )
        let encoded = try Codec.encode(export)
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var windows = try #require(root["correlationWindows"] as? [[String: Any]])
        let started = try #require(windows[0]["startedAtUptimeNanoseconds"] as? NSNumber).uint64Value
        windows[0]["endedAtUptimeNanoseconds"] = NSNumber(value: started + 1)
        root["correlationWindows"] = windows
        let tampered = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: Error.self) {
            _ = try Codec.decodeAndVerify(tampered)
        }
    }

    private var setup: PassiveBluetoothStationaryCaptureSetup {
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
                    "Capture Build V14-duration-redteam",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    "12345678-90ab-cdef-1234-567890abcdef",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    "0123456789abcdef0123456789abcdef01234567"
            ],
            executableData: Data("duration-policy-fixture".utf8)
        )
    }

    private func makePowerCycleResult(
        windowDurationNanoseconds: UInt64
    ) throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(minimumWindowDurationNanoseconds: 1)
        let stride = PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds + 1_000

        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: stride,
            endedAtUptimeNanoseconds: stride + windowDurationNanoseconds,
            candidates: [candidate(neighbor)]
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: stride * 2,
            endedAtUptimeNanoseconds: stride * 2 + windowDurationNanoseconds,
            candidates: [candidate(neighbor), candidate(scooter)]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: stride * 3,
            endedAtUptimeNanoseconds: stride * 3 + windowDurationNanoseconds,
            candidates: [candidate(neighbor)]
        )
        return try #require(ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: stride * 4,
            endedAtUptimeNanoseconds: stride * 4 + windowDurationNanoseconds,
            candidates: [candidate(neighbor), candidate(scooter)]
        ))
    }

    private func candidate(
        _ id: UUID
    ) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
        .init(id: id, isConnectable: true)
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
        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}
