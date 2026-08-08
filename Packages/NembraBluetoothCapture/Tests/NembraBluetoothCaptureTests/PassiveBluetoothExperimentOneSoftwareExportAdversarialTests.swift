import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothExperimentOneSoftwareExportAdversarialTests {
    private let target = "11111111-2222-3333-4444-555555555555"

    @Test
    func nestedAuthorityLikeFieldsAreRejectedClosedWorld() throws {
        var buildInjected = makeWireObject()
        var build = try #require(buildInjected["build"] as? [String: Any])
        build["fieldAuthorized"] = true
        buildInjected["build"] = build
        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .unexpectedWireField("build.fieldAuthorized")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(
                encode(buildInjected)
            )
        }

        var windowInjected = makeWireObject()
        var windows = try #require(windowInjected["correlationWindows"] as? [[String: Any]])
        windows[0]["physicallyVerified"] = true
        windowInjected["correlationWindows"] = windows
        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .unexpectedWireField("correlationWindows[0].physicallyVerified")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(
                encode(windowInjected)
            )
        }

        var candidateInjected = makeWireObject()
        var candidateWindows = try #require(candidateInjected["correlationWindows"] as? [[String: Any]])
        var candidates = try #require(candidateWindows[1]["candidates"] as? [[String: Any]])
        candidates[0]["authenticatedES80"] = true
        candidateWindows[1]["candidates"] = candidates
        candidateInjected["correlationWindows"] = candidateWindows
        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .unexpectedWireField("correlationWindows[1].candidates[0].authenticatedES80")
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(
                encode(candidateInjected)
            )
        }
    }

    @Test
    func tamperedShortPowerWindowCannotReplayAsExperimentOneEvidence() throws {
        var object = makeWireObject()
        var windows = try #require(object["correlationWindows"] as? [[String: Any]])
        let start = try #require(windows[0]["startedAtUptimeNanoseconds"] as? UInt64)
        windows[0]["endedAtUptimeNanoseconds"] = start + 9_999_999_999
        object["correlationWindows"] = windows

        #expect(throws: PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(encode(object))
        }
    }

    @Test
    func serializedWindowSequenceMustRemainExactProducerSequence() throws {
        var object = makeWireObject()
        var windows = try #require(object["correlationWindows"] as? [[String: Any]])
        windows[0]["windowSequence"] = UInt64(10)
        windows[1]["windowSequence"] = UInt64(20)
        windows[2]["windowSequence"] = UInt64(30)
        windows[3]["windowSequence"] = UInt64(40)
        object["correlationWindows"] = windows

        #expect(
            throws: PassiveBluetoothExperimentOneSoftwareExportError
                .correlationWindowSequenceMismatch(index: 0)
        ) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(encode(object))
        }
    }

    @Test
    func serializedPowerWindowsCannotOverlapInLocalReceiptChronology() throws {
        var object = makeWireObject()
        var windows = try #require(object["correlationWindows"] as? [[String: Any]])
        windows[1]["startedAtUptimeNanoseconds"] = UInt64(9_000_000_000)
        windows[1]["endedAtUptimeNanoseconds"] = UInt64(19_000_000_000)
        object["correlationWindows"] = windows

        #expect(throws: PassiveBluetoothExperimentOneSoftwareExportError.correlationEvidenceInvalid) {
            _ = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(encode(object))
        }
    }

    private func makeWireObject() -> [String: Any] {
        let targetCandidate: [String: Any] = [
            "peripheralIdentifier": target,
            "isConnectable": true
        ]
        let starts: [UInt64] = [0, 20_000_000_000, 40_000_000_000, 60_000_000_000]
        let candidateSets: [[[String: Any]]] = [[], [targetCandidate], [], [targetCandidate]]
        let windows: [[String: Any]] = (0..<4).map { index in
            [
                "phase": index,
                "windowSequence": UInt64(index + 1),
                "startedAtUptimeNanoseconds": starts[index],
                "endedAtUptimeNanoseconds": starts[index] + 10_000_000_000,
                "candidates": candidateSets[index]
            ]
        }

        return [
            "schemaVersion": PassiveBluetoothExperimentOneSoftwareExport.currentSchemaVersion,
            "experimentRecipeID": PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue,
            "captureJSONBase64": "",
            "stationaryManifestJSONBase64": "",
            "correlationWindows": windows,
            "build": [
                "buildIdentifier": "Capture Build V14-test",
                "buildInstanceID": "a1b2c3d4-e5f6-47a8-90bc-def123456789",
                "sourceCommitSHA": "abcdef0123456789abcdef0123456789abcdef01",
                "executableSHA256": String(repeating: "a", count: 64)
            ]
        ]
    }

    private func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
