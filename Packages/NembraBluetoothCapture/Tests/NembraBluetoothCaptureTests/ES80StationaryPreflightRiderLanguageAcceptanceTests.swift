import Foundation
import Testing

@Suite("ES80 stationary preflight rider-language acceptance")
struct ES80StationaryPreflightRiderLanguageAcceptanceTests {
    private static func appSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("App")
                .appendingPathComponent("NembraApp.swift"),
            encoding: .utf8
        )
    }

    private static func stationaryPreflight(in source: String) throws -> Substring {
        let beginning = try #require(
            source.range(of: "private struct ES80ExperimentOneStationaryPreflightView")
        )
        let end = try #require(
            source.range(
                of: "private struct ES80ExperimentOneFieldNoGoView",
                range: beginning.lowerBound..<source.endIndex
            )
        )
        return source[beginning.lowerBound..<end.lowerBound]
    }

    @Test("primary charger preflight does not expose the engineering recipe token")
    func primaryPreflightStaysHumanFirst() throws {
        let source = try Self.appSource()
        let preflight = try Self.stationaryPreflight(in: source)

        #expect(!preflight.contains("Required for ES80-FINGERPRINT-v1"))
        #expect(!preflight.contains("ES80-FINGERPRINT-v1"))
        #expect(preflight.contains("Required for this capture"))
        #expect(preflight.contains("Disconnected"))
        #expect(preflight.contains("Connected"))
        #expect(preflight.contains("Disconnect charger to continue"))
        #expect(preflight.contains("Continue to setup confirmation"))
        #expect(preflight.contains("Nembra cannot sense the charger directly"))
    }

    @Test("copy cleanup cannot weaken charger admission or fresh-run reset")
    func chargerTruthAndResetRemainMechanical() throws {
        let source = try Self.appSource()
        let preflight = try Self.stationaryPreflight(in: source)

        #expect(source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure"))
        #expect(preflight.contains("PassiveBluetoothStationaryCaptureChargerState.disconnected.rawValue"))
        #expect(preflight.contains(".disabled(!canContinue)"))
        #expect(preflight.contains("selectedChargerState = nil"))
        #expect(preflight.contains("disconnectedDeclarationAccepted = false"))
        #expect(preflight.contains("es80.capture.preflight.charger-blocked"))
        #expect(preflight.contains("es80.capture.preflight.continue"))
        #expect(preflight.contains("es80.capture.stationary-preflight"))
    }
}
