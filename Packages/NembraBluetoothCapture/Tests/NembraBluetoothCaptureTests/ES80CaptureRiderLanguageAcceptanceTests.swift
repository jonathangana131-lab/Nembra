import Foundation
import Testing

@Suite("ES80 Capture rider-language acceptance")
struct ES80CaptureRiderLanguageAcceptanceTests {
    private static func repositoryRoot() -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
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

    private static func riderSurface(in source: String) throws -> Substring {
        let beginning = try #require(source.range(of: "private var passiveSafetyPanel"))
        let details = try #require(
            source.range(
                of: "private var captureDetailsSheet",
                range: beginning.lowerBound..<source.endIndex
            )
        )
        return source[beginning.lowerBound..<details.lowerBound]
    }

    private static func stationaryPreflightSurface(in source: String) throws -> Substring {
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

    @Test("stationary preflight stays rider-first while exact recipe truth remains available")
    func stationaryPreflightStaysHumanFirst() throws {
        let source = try Self.appSource()
        let preflight = try Self.stationaryPreflightSurface(in: source)

        #expect(!preflight.contains("Required for ES80-FINGERPRINT-v1"))
        #expect(!preflight.contains("Continue to setup confirmation"))
        #expect(preflight.contains("Required for this capture"))
        #expect(preflight.contains("Label(\"Confirm setup\""))
        #expect(preflight.contains("es80.capture.preflight.continue"))

        #expect(source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue"))
        #expect(source.contains("private var recipeID: String"))
        #expect(source.contains("Text(recipeID)"))
    }

    @Test("primary Capture states use rider language instead of implementation vocabulary")
    func primaryStatesStayHumanFirst() throws {
        let source = try Self.shellSource()
        let riderSurface = try Self.riderSurface(in: source)

        let engineeringPhrasesThatMustStayOutOfPrimaryCopy = [
            "One sealed evidence life",
            "package-owned Experiment One authority",
            "package-owned physical execution gate",
            "producer's evidence clock",
            "producer accepts the window only from its own monotonic receipt boundary",
            "full CoreBluetooth identifier",
            "post-admission scan",
            "fresh scan epoch created after the sealed admission",
            "package-owned correlated target",
            "finite acquisition",
            "accepted Horizon authority",
            "accepted monotonic observation interval",
            "package-owned Ready epoch",
            "committing Horizon",
            "immutable JSON artifact",
            "Evidence failed closed",
            "bounded CoreBluetooth advertisement catalog",
            "package-owned outer, SoftwareExport, and immutable Capture integrity checks"
        ]

        for phrase in engineeringPhrasesThatMustStayOutOfPrimaryCopy {
            #expect(
                !riderSurface.contains(phrase),
                "Primary Capture copy still exposes engineering vocabulary: \(phrase)"
            )
        }

        #expect(riderSurface.contains("PASSIVE / READ ONLY"))
        #expect(riderSurface.contains("Scooter OFF"))
        #expect(riderSurface.contains("Scooter ON"))
        #expect(riderSurface.contains("Share Capture"))
        #expect(riderSurface.contains("View Details"))
    }

    @Test("engineering truth remains available in Details instead of being deleted")
    func technicalTruthRemainsInDetails() throws {
        let source = try Self.shellSource()
        let detailsStart = try #require(source.range(of: "private var captureDetailsSheet"))
        let details = source[detailsStart.lowerBound..<source.endIndex]

        #expect(details.contains("Truth boundary"))
        #expect(details.contains("CoreBluetooth"))
        #expect(details.contains("Software Export SHA-256"))
        #expect(details.contains("Runtime executable SHA-256"))
        #expect(details.contains("does not authenticate the physical ES80"))
    }

    @Test("language cleanup cannot weaken physical lock, evidence authority, or stable UI actions")
    func truthAndActionContractsRemainStable() throws {
        let source = try Self.shellSource()

        #expect(source.contains("guard status.physicalProcedurePermitted else"))
        #expect(source.contains("declaredStationarySetup = nil"))
        #expect(source.contains("PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)"))
        #expect(source.contains("finalShareIntegrityReport != nil"))

        let stableActionIdentifiers = [
            "es80.capture.begin-window",
            "es80.capture.confirm-setup",
            "es80.capture.complete-window",
            "es80.capture.restart-correlation",
            "es80.capture.confirm-correlated-target",
            "es80.capture.restart-rediscovery",
            "es80.capture.connect-prepared-target",
            "es80.capture.finish",
            "es80.capture.share",
            "es80.capture.prepare-share",
            "es80.capture.share-unavailable",
            "es80.capture.view-details",
            "es80.capture.restart-experiment",
            "es80.capture.experiment-progress",
            "es80.capture.single-authority",
            "es80.capture.complete",
            "es80.capture-shell"
        ]

        for identifier in stableActionIdentifiers {
            #expect(source.contains(identifier), "Missing stable Capture action/state identifier: \(identifier)")
        }
    }
}
