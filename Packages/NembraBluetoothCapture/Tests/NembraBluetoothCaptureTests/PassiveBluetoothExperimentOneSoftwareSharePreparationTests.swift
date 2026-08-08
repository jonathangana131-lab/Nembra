import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One software Share preparation")
struct PassiveBluetoothExperimentOneSoftwareSharePreparationTests {
    private let scooter = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let neighbor = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let buildInstance = "12345678-90ab-cdef-1234-567890abcdef"
    private let commit = "0123456789abcdef0123456789abcdef01234567"

    @Test("prepared Share is the package software export rather than raw controller JSON")
    func preparesPackageOwnedSoftwareExport() throws {
        let captureJSON = try makeCaptureJSON()
        let result = try makePowerCycleResult()
        let identity = try makeBuildIdentity()
        let declaredSetup = setup()

        let prepared = try PassiveBluetoothExperimentOneSoftwareSharePreparation.prepare(
            captureJSON: captureJSON,
            powerCycleResult: result,
            runtimeBuildIdentity: identity,
            setup: declaredSetup,
            prettyPrinted: false
        )

        #expect(prepared.softwareExportJSON != captureJSON)
        #expect(prepared.captureByteCount == captureJSON.count)
        #expect(prepared.experimentRecipeID == .es80FingerprintV1)
        #expect(prepared.buildIdentifier == identity.buildIdentifier)
        #expect(prepared.buildInstanceID == identity.buildInstanceID)
        #expect(prepared.sourceCommitSHA == identity.sourceCommitSHA)
        #expect(prepared.executableSHA256 == identity.executableSHA256)

        let verified = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(
            prepared.softwareExportJSON
        )
        #expect(verified.captureJSON == captureJSON)
        #expect(verified.correlationWindows.count == 4)
        #expect(Set(verified.correlationWindows.map(\.observationSeriesIdentity)).count == 1)

        let manifest = try PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(
            manifestJSON: verified.stationaryManifestJSON,
            captureJSON: captureJSON
        )
        #expect(manifest.setup == declaredSetup)
        #expect(manifest.nembraBuildIdentifier == identity.buildIdentifier)
        #expect(manifest.nembraBuildInstanceID == identity.buildInstanceID)
        #expect(manifest.nembraBuildCommitSHA == identity.sourceCommitSHA)
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
        var ledger = PassiveBluetoothPowerCycleObservationLedger(minimumWindowDurationNanoseconds: 1)
        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 10,
            endedAtUptimeNanoseconds: 11,
            candidates: [candidate(neighbor)]
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: 20,
            endedAtUptimeNanoseconds: 21,
            candidates: [candidate(neighbor), candidate(scooter)]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: 30,
            endedAtUptimeNanoseconds: 31,
            candidates: [candidate(neighbor)]
        )
        return try #require(ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 40,
            endedAtUptimeNanoseconds: 41,
            candidates: [candidate(neighbor), candidate(scooter)]
        ))
    }

    private func candidate(_ id: UUID) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
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
