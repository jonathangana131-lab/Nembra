import Foundation
import Testing

@Suite("ES80 Capture stationary-preflight rider language")
struct ES80CaptureStationaryPreflightRiderLanguageAcceptanceTests {
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
        let fieldNoGo = try #require(
            source.range(
                of: "private struct ES80ExperimentOneFieldNoGoView",
                range: beginning.lowerBound..<source.endIndex
            )
        )
        return source[beginning.lowerBound..<fieldNoGo.lowerBound]
    }

    @Test("stationary preflight keeps recipe identifiers out of the rider path")
    func preflightIsHumanFirst() throws {
        let source = try Self.appSource()
        let preflight = try Self.stationaryPreflight(in: source)

        #expect(!preflight.contains("ES80-FINGERPRINT-v1"))
        #expect(preflight.contains("Stationary preflight"))
        #expect(preflight.contains("Confirm the charger state before OFF 1 becomes available."))
        #expect(preflight.contains("Disconnected"))
        #expect(preflight.contains("Keep unplugged for the whole capture"))
        #expect(preflight.contains("Unplug charger to continue"))
    }

    @Test("language cleanup preserves charger fail-closed and fresh-run reset")
    func physicalPreflightTruthRemainsFailClosed() throws {
        let source = try Self.appSource()
        let preflight = try Self.stationaryPreflight(in: source)

        #expect(source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure"))
        #expect(preflight.contains("selectedChargerState?.rawValue"))
        #expect(preflight.contains("PassiveBluetoothStationaryCaptureChargerState.disconnected.rawValue"))
        #expect(preflight.contains(".disabled(!canContinue)"))
        #expect(preflight.contains("selectedChargerState = nil"))
        #expect(preflight.contains("disconnectedDeclarationAccepted = false"))
        #expect(preflight.contains("es80.capture.preflight.continue"))
    }

    @Test("exact recipe identity remains subordinate in engineering truth")
    func recipeIdentityStillExistsOutsidePreflight() throws {
        let source = try Self.appSource()
        let preflight = try Self.stationaryPreflight(in: source)

        #expect(!preflight.contains("ES80-FINGERPRINT-v1"))
        #expect(source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue"))
        #expect(source.contains("Text(recipeID)"))
        #expect(source.contains("Engineering details"))
    }
}
