import Foundation
import Testing

@Suite("ES80 Capture human-first field flow")
struct ES80CaptureHumanFirstFieldFlowAcceptanceTests {
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

    private static func slice(
        _ source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try #require(source.range(of: startMarker))
        let end = try #require(
            source.range(
                of: endMarker,
                range: start.lowerBound..<source.endIndex
            )
        )
        return source[start.lowerBound..<end.lowerBound]
    }

    @Test("primary capture cards and progress use rider language")
    func primaryFlowIsHumanFirst() throws {
        let source = try Self.shellSource()
        let primary = try Self.slice(
            source,
            from: "private func hero(for phase: Phase)",
            to: "private var captureDetailsSheet"
        )

        let banned = [
            "Text(\"EXPERIMENT ONE\")",
            "FIELD AUTHORITY",
            "CORRELATION STOPPED",
            "NO UNIQUE TARGET",
            "AMBIGUOUS TARGET",
            "CORRELATED TARGET",
            "PASSIVE CONNECTION",
            "PASSIVE DISCOVERY",
            "Begin OFF 1 window",
            "Repeat all four windows",
            "Confirm correlated target",
            "Restart rediscovery",
            "HORIZON READY"
        ]

        for phrase in banned {
            #expect(!primary.contains(phrase), "Primary field copy still exposes implementation vocabulary: \(phrase)")
        }

        #expect(primary.contains("CAPTURE PROGRESS"))
        #expect(primary.contains("CAPTURE LOCKED"))
        #expect(primary.contains("Begin OFF 1 check"))
        #expect(primary.contains("Confirm scooter signal"))
        #expect(primary.contains("READ-ONLY CONNECTION"))
        #expect(primary.contains("READ-ONLY DISCOVERY"))
        #expect(primary.contains("READY TO SEAL"))
        #expect(primary.contains("healthItem(\"SIGNAL\""))
        #expect(primary.contains("healthItem(\"DISCOVERY\""))
        #expect(primary.contains("healthItem(\"SEAL\""))
    }

    @Test("share recovery and progress helpers stay human-first")
    func recoveryAndProgressAreHumanFirst() throws {
        let source = try Self.shellSource()
        let recovery = try Self.slice(
            source,
            from: "private func prepareFinalShareForAnalysisAndSharing",
            to: "private func statePanel("
        )
        let progress = try Self.slice(
            source,
            from: "private func progressStage(",
            to: "private func phaseShortName("
        )

        let recoveryLeaks = [
            "setup provenance at export time",
            "temporary Share file could not be staged",
            "did not earn analysis readiness",
            "replaying consumed authority",
            "String(describing: error)",
            "fresh Experiment One",
            "correlated target",
            "correlation window",
            "observation window"
        ]
        for phrase in recoveryLeaks {
            #expect(!recovery.contains(phrase), "Recovery copy still exposes implementation vocabulary: \(phrase)")
        }

        #expect(recovery.contains("could not prepare the Share file"))
        #expect(recovery.contains("final Share file did not pass every required check"))
        #expect(recovery.contains("start a fresh capture"))

        #expect(!progress.contains("Experiment One progress"))
        #expect(!progress.contains("REACQUIRE"))
        #expect(progress.contains("Capture progress"))
        #expect(progress.contains("SEAL READY"))
        #expect(progress.contains("MATCH"))
    }

    @Test("stationary preflight hides the recipe token without weakening field gates")
    func stationaryPreflightIsHumanFirstAndFailClosed() throws {
        let source = try Self.appSource()
        let preflight = try Self.slice(
            source,
            from: "private struct ES80ExperimentOneStationaryPreflightView",
            to: "private struct ES80ExperimentOneFieldNoGoView"
        )

        #expect(!preflight.contains("ES80-FINGERPRINT-v1"))
        #expect(preflight.contains("Keep unplugged for the whole capture"))
        #expect(preflight.contains("Unplug charger to continue"))
        #expect(preflight.contains(".disabled(!canContinue)"))
        #expect(preflight.contains("selectedChargerState = nil"))
        #expect(preflight.contains("disconnectedDeclarationAccepted = false"))

        #expect(source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure"))
        #expect(source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue"))
        #expect(source.contains("Text(recipeID)"))
    }

    @Test("language cleanup preserves evidence and action authority")
    func truthAuthorityIsUnchanged() throws {
        let source = try Self.shellSource()

        #expect(source.contains("guard status.physicalProcedurePermitted else"))
        #expect(source.contains("PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)"))
        #expect(source.contains("finalShareIntegrityReport != nil"))
        #expect(source.contains("declaredStationarySetup = nil"))
        #expect(source.contains("Text(\"Truth boundary\")"))
        #expect(source.contains("CoreBluetooth correlation uses full peripheral identity"))
        #expect(source.contains("does not authenticate the physical ES80"))

        for identifier in [
            "es80.capture.begin-window",
            "es80.capture.complete-window",
            "es80.capture.confirm-correlated-target",
            "es80.capture.connect-prepared-target",
            "es80.capture.finish",
            "es80.capture.share",
            "es80.capture.view-details",
            "es80.capture.restart-experiment",
            "es80.capture.complete",
            "es80.capture-shell"
        ] {
            #expect(source.contains(identifier), "Stable Capture action/state identifier missing: \(identifier)")
        }
    }
}
