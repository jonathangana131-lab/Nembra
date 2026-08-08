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

    private static func preflightSurface(in source: String) throws -> Substring {
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

    @Test("primary stationary preflight stays rider-first without weakening its gate")
    func primaryPreflightStaysHumanFirst() throws {
        let source = try Self.appSource()
        let preflight = try Self.preflightSurface(in: source)

        #expect(!preflight.contains("Required for ES80-FINGERPRINT-v1"))
        #expect(!preflight.contains("Continue to setup confirmation"))
        #expect(preflight.contains("Required for this capture"))
        #expect(preflight.contains("Label(\"Confirm setup\""))

        #expect(preflight.contains("PassiveBluetoothStationaryCaptureChargerState.disconnected.rawValue"))
        #expect(preflight.contains("disconnectedDeclarationAccepted = true"))
        #expect(preflight.contains(".disabled(!canContinue)"))
        #expect(preflight.contains("es80.capture.preflight.charger-disconnected"))
        #expect(preflight.contains("es80.capture.preflight.charger-connected"))
        #expect(preflight.contains("es80.capture.preflight.charger-blocked"))
        #expect(preflight.contains("es80.capture.preflight.continue"))

        #expect(source.contains("fieldRecipe == PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue"))
        #expect(source.contains("private var recipeID: String"))
        #expect(source.contains("Text(recipeID)"))
    }
}
