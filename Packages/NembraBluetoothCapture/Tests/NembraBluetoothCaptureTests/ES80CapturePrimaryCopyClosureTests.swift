import Foundation
import Testing

@Suite("ES80 Capture primary-copy closure")
struct ES80CapturePrimaryCopyClosureTests {
    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func shellSource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("Features")
                .appendingPathComponent("Research")
                .appendingPathComponent("ES80CaptureShellView.swift"),
            encoding: .utf8
        )
    }

    private static func appSource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
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

    @Test("known engineering vocabulary cannot reappear through primary helper strings")
    func primaryHelperVocabularyStaysHumanFirst() throws {
        let source = try Self.shellSource()

        let forbiddenPrimaryOrHelperFragments = [
            "full Bluetooth identifier",
            "FIELD AUTHORITY",
            "PASSIVE ACQUISITION",
            "healthItem(\"FINITE\"",
            "healthItem(\"HORIZON\"",
            "The package producer, not this timer",
            "Available only after the package accepts the required monotonic observation duration",
            "package-owned CoreBluetooth controller",
            "package-owned Experiment One workflow",
            "producer's monotonic receipt window",
            "post-admission scan",
            "accepted Ready epoch",
            "authoritative receipt window",
            "CoreBluetooth never confirmed scan readiness",
            "CoreBluetooth scan became inactive",
            "case .acquiring: return \"Finite acquisition\"",
            "case .readyToSeal: return \"Horizon ready\"",
            "case .finalizing: return \"Sealing artifact\""
        ]

        for fragment in forbiddenPrimaryOrHelperFragments {
            #expect(
                !source.contains(fragment),
                "Primary Capture helper copy still exposes implementation vocabulary: \(fragment)"
            )
        }

        #expect(source.contains("FIELD STATUS"))
        #expect(source.contains("PASSIVE DISCOVERY"))
        #expect(source.contains("healthItem(\"DISCOVERY\""))
        #expect(source.contains("healthItem(\"DURATION\""))
        #expect(source.contains("case .acquiring: return \"Read-only discovery\""))
        #expect(source.contains("case .readyToSeal: return \"Ready to seal\""))
        #expect(source.contains("case .finalizing: return \"Sealing capture\""))
    }

    @Test("technical truth remains available in Capture Details")
    func technicalTruthRemainsAvailable() throws {
        let source = try Self.shellSource()
        let detailsStart = try #require(source.range(of: "private var captureDetailsSheet"))
        let details = source[detailsStart.lowerBound..<source.endIndex]

        #expect(details.contains("Truth boundary"))
        #expect(details.contains("CoreBluetooth"))
        #expect(details.contains("Software Export SHA-256"))
        #expect(details.contains("Runtime executable SHA-256"))
        #expect(details.contains("does not authenticate the physical ES80"))
    }

    @Test("stationary preflight keeps the recipe token out of primary rider copy")
    func stationaryPreflightStaysHumanFirst() throws {
        let source = try Self.appSource()
        let preflight = try Self.stationaryPreflight(in: source)

        #expect(!preflight.contains("ES80-FINGERPRINT-v1"))
        #expect(preflight.contains("Required for this capture"))
        #expect(preflight.contains("Disconnected"))
        #expect(preflight.contains("Connected"))
        #expect(preflight.contains("Disconnect charger to continue"))
        #expect(preflight.contains("Continue to setup confirmation"))
        #expect(preflight.contains("Nembra cannot sense the charger directly"))
    }

    @Test("copy closure cannot weaken physical admission or fresh-run reset")
    func physicalAdmissionAndResetRemainMechanical() throws {
        let app = try Self.appSource()
        let preflight = try Self.stationaryPreflight(in: app)
        let shell = try Self.shellSource()

        #expect(app.contains("PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure"))
        #expect(preflight.contains("PassiveBluetoothStationaryCaptureChargerState.disconnected.rawValue"))
        #expect(preflight.contains(".disabled(!canContinue)"))
        #expect(preflight.contains("selectedChargerState = nil"))
        #expect(preflight.contains("disconnectedDeclarationAccepted = false"))
        #expect(preflight.contains("es80.capture.preflight.charger-blocked"))
        #expect(preflight.contains("es80.capture.preflight.continue"))
        #expect(preflight.contains("es80.capture.stationary-preflight"))

        #expect(shell.contains("guard status.physicalProcedurePermitted else"))
        #expect(shell.contains("PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)"))
        #expect(shell.contains("finalShareIntegrityReport != nil"))
        #expect(shell.contains("PASSIVE / READ ONLY"))
        #expect(shell.contains("Share Capture"))
        #expect(shell.contains("View Details"))
    }
}
