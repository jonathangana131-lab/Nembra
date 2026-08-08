import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Experiment One software export hardening")
struct PassiveBluetoothExperimentOneSoftwareExportHardeningTests {
    private let target = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let other = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let observationSeriesIdentity = UUID(
        uuidString: "99999999-8888-7777-6666-555555555555"
    )!
    private let sessionID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
    private let buildIdentifier = "Capture Build V14-F1"
    private let buildInstanceID = "12345678-90ab-cdef-1234-567890abcdef"
    private let sourceCommitSHA = "0123456789abcdef0123456789abcdef01234567"
    private let executableSHA256 = String(repeating: "a", count: 64)

    @Test("valid imported envelope preserves the exact observation-series identity")
    func validEnvelopePreservesObservationSeriesIdentity() throws {
        let wire = try makeWire()
        let encoded = try JSONSerialization.data(withJSONObject: wire, options: [.sortedKeys])

        let decoded = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(encoded)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.experimentRecipeID == .es80FingerprintV1)
        #expect(decoded.correlationObservationSeriesIdentity == observationSeriesIdentity)
        #expect(decoded.correlationWindows.count == 4)
        #expect(decoded.correlationWindows[1].candidates.contains {
            $0.peripheralIdentifier == target
        })
        #expect(decoded.build.buildInstanceID == buildInstanceID)
        #expect(decoded.build.executableSHA256 == executableSHA256)
    }

    @Test("nested build authority fields fail closed instead of being ignored")
    func nestedBuildAuthorityFieldFailsClosed() throws {
        var wire = try makeWire()
        var build = try #require(wire["build"] as? [String: Any])
        build["fieldAuthorized"] = true
        wire["build"] = build
        let encoded = try JSONSerialization.data(withJSONObject: wire, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .unexpectedWireField("build.fieldAuthorized")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(encoded)
        }
    }

    @Test("nested candidate authentication fields fail closed instead of being ignored")
    func nestedCandidateAuthorityFieldFailsClosed() throws {
        var wire = try makeWire()
        var windows = try #require(wire["correlationWindows"] as? [[String: Any]])
        var secondOn = windows[3]
        var candidates = try #require(secondOn["candidates"] as? [[String: Any]])
        var targetCandidate = candidates[1]
        targetCandidate["authenticatedES80"] = true
        candidates[1] = targetCandidate
        secondOn["candidates"] = candidates
        windows[3] = secondOn
        wire["correlationWindows"] = windows
        let encoded = try JSONSerialization.data(withJSONObject: wire, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .unexpectedWireField("correlationWindows[3].candidates[1].authenticatedES80")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(encoded)
        }
    }

    @Test("noncanonical observation-series identity cannot be repaired on import")
    func noncanonicalObservationSeriesIdentityFailsClosed() throws {
        var wire = try makeWire()
        wire["correlationObservationSeriesIdentity"] = observationSeriesIdentity.uuidString.lowercased()
        let encoded = try JSONSerialization.data(withJSONObject: wire, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothExperimentOneSoftwareExportError.malformedWireData) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(encoded)
        }
    }

    @Test("correlation catalogs are replayed and cannot retain a stale success disposition")
    func changedCorrelationCatalogFailsClosed() throws {
        var wire = try makeWire()
        var windows = try #require(wire["correlationWindows"] as? [[String: Any]])
        var secondOn = windows[3]
        secondOn["candidates"] = [[
            "peripheralIdentifier": other.uuidString,
            "isConnectable": true,
        ]]
        windows[3] = secondOn
        wire["correlationWindows"] = windows
        let encoded = try JSONSerialization.data(withJSONObject: wire, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothExperimentOneSoftwareExportError.correlationNotUnique) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(encoded)
        }
    }

    private func makeWire() throws -> [String: Any] {
        let captureJSON = try makeCaptureJSON()
        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.make(
            captureJSON: captureJSON,
            experimentRecipe: .es80FingerprintV1,
            nembraBuildIdentifier: buildIdentifier,
            nembraBuildInstanceID: buildInstanceID,
            nembraBuildCommitSHA: sourceCommitSHA,
            selectedPeripheralIdentifier: target.uuidString,
            setup: .init(
                chargerState: .disconnected,
                executionContext: .foregroundUnlockedScreenOn,
                stockAppReferenceSetup: .none
            )
        )
        let manifestJSON = try PassiveBluetoothStationaryCaptureManifestJSON.encode(manifest)

        return [
            "schemaVersion": 1,
            "experimentRecipeID": PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue,
            "captureJSONBase64": captureJSON.base64EncodedString(),
            "stationaryManifestJSONBase64": manifestJSON.base64EncodedString(),
            "correlationObservationSeriesIdentity": observationSeriesIdentity.uuidString,
            "correlationWindows": makeCorrelationWindows(),
            "build": [
                "buildIdentifier": buildIdentifier,
                "buildInstanceID": buildInstanceID,
                "sourceCommitSHA": sourceCommitSHA,
                "executableSHA256": executableSHA256,
            ],
        ]
    }

    private func makeCorrelationWindows() -> [[String: Any]] {
        let unrelated: [String: Any] = [
            "peripheralIdentifier": other.uuidString,
            "isConnectable": true,
        ]
        let selected: [String: Any] = [
            "peripheralIdentifier": target.uuidString,
            "isConnectable": true,
        ]

        return [
            makeWindow(phase: 0, sequence: 1, start: 10, end: 11, candidates: [unrelated]),
            makeWindow(
                phase: 1,
                sequence: 2,
                start: 20,
                end: 21,
                candidates: [unrelated, selected]
            ),
            makeWindow(phase: 2, sequence: 3, start: 30, end: 31, candidates: [unrelated]),
            makeWindow(
                phase: 3,
                sequence: 4,
                start: 40,
                end: 41,
                candidates: [unrelated, selected]
            ),
        ]
    }

    private func makeWindow(
        phase: Int,
        sequence: UInt64,
        start: UInt64,
        end: UInt64,
        candidates: [[String: Any]]
    ) -> [String: Any] {
        [
            "phase": phase,
            "windowSequence": sequence,
            "startedAtUptimeNanoseconds": start,
            "endedAtUptimeNanoseconds": end,
            "candidates": candidates,
        ]
    }

    private func makeCaptureJSON() throws -> Data {
        var session = try PassiveBluetoothCaptureSession(
            id: sessionID,
            vehicleIdentity: VehicleIdentity(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "AOVOPRO ES80",
                protocolFamily: "unverified-tuya"
            ),
            startedAt: startedAt
        )
        var sequence: UInt64 = 1

        func append(_ event: PassiveBluetoothCaptureEvent) throws {
            try session.append(
                event,
                sequenceNumber: sequence,
                receivedAtUptimeNanoseconds: sequence,
                receivedAtDate: startedAt.addingTimeInterval(Double(sequence))
            )
            sequence += 1
        }

        try append(.service(try PassiveBluetoothServiceObservation(
            peripheralIdentifier: target.uuidString,
            serviceUUID: "FFE0",
            isPrimary: true
        )))
        try append(.characteristic(try PassiveBluetoothCharacteristicObservation(
            peripheralIdentifier: target.uuidString,
            serviceUUID: "FFE0",
            characteristicUUID: "FFE1",
            properties: [.notify]
        )))
        try append(.value(try PassiveBluetoothValueObservation(
            peripheralIdentifier: target.uuidString,
            serviceUUID: "FFE0",
            characteristicUUID: "FFE1",
            origin: .subscriptionUpdate,
            payload: Data([0x01, 0x02])
        )))

        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}
