import Foundation
import Testing

@Suite("ES80 Capture preflight rider-language acceptance")
struct ES80CapturePreflightRiderLanguageAcceptanceTests {
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

    @Test("stationary preflight keeps exact recipe identifiers out of primary rider copy")
    func primaryPreflightIsHumanFirst() throws {
        let source = try Self.appSource()
        let preflight = try Self.stationaryPreflight(in: source)

        #expect(!preflight.contains("ES80-FINGERPRINT-v1"))
        #expect(preflight.contains("Required before OFF 1"))
        #expect(preflight.contains("Disconnected"))
        #expect(preflight.contains("Connected"))
        #expect(preflight.contains("Nembra cannot sense the charger directly"))
    }

    @Test("copy cleanup cannot weaken charger gate or fresh-run reset")
    func chargerTruthAndActionsRemainStable() throws {
        let source = try Self.appSource()
        let preflight = try Self.stationaryPreflight(in: source)

        #expect(preflight.contains("PassiveBluetoothStationaryCaptureChargerState.disconnected.rawValue"))
        #expect(preflight.contains("guard selectedChargerState?.rawValue"))
        #expect(preflight.contains("selectedChargerState = nil"))
        #expect(preflight.contains("disconnectedDeclarationAccepted = false"))
        #expect(preflight.contains("es80.capture.stationary-preflight"))
        #expect(preflight.contains("es80.capture.preflight.charger-blocked"))
        #expect(preflight.contains("es80.capture.preflight.continue"))
    }

    @Test("exact recipe identity remains available under engineering details")
    func recipeIdentityRemainsInDetails() throws {
        let source = try Self.appSource()
        let detailsStart = try #require(
            source.range(of: "private struct ES80ExperimentOneFieldNoGoView")
        )
        let details = source[detailsStart.lowerBound..<source.endIndex]

        #expect(details.contains("Text(\"Engineering details\")"))
        #expect(details.contains("Text(recipeID)"))
        #expect(details.contains("es80.capture.recipe-id"))
        #expect(details.contains("Physical authorization"))
        #expect(details.contains("NO-GO"))
    }
}
