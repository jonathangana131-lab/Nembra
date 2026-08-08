import Foundation
import Testing

@Suite("ES80 Capture Share and progress rider language")
struct ES80CaptureShareProgressRiderLanguageAcceptanceTests {
    private static func shellSource() throws -> String {
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
                .appendingPathComponent("Features")
                .appendingPathComponent("Research")
                .appendingPathComponent("ES80CaptureShellView.swift"),
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

    @Test("primary cards use field language instead of research vocabulary")
    func primaryCardsStayHumanFirst() throws {
        let source = try Self.shellSource()
        let primary = try Self.slice(
            source,
            from: "private func hero(for phase: Phase)",
            to: "private var captureDetailsSheet"
        )

        let leaks = [
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

        for leak in leaks {
            #expect(!primary.contains(leak), "Primary Capture copy still exposes research vocabulary: \(leak)")
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

    @Test("Share and recovery copy explains user action without export internals")
    func shareRecoveryStaysHumanFirst() throws {
        let source = try Self.shellSource()
        let recovery = try Self.slice(
            source,
            from: "private func prepareFinalShareForAnalysisAndSharing",
            to: "private func statePanel("
        )

        let leaks = [
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

        for leak in leaks {
            #expect(!recovery.contains(leak), "Share/recovery copy still exposes implementation vocabulary: \(leak)")
        }

        #expect(recovery.contains("could not prepare the Share file"))
        #expect(recovery.contains("final Share file did not pass every required check"))
        #expect(recovery.contains("start a fresh capture"))
    }

    @Test("progress, hero, and status language stays rider-first")
    func progressAndStatusStayHumanFirst() throws {
        let source = try Self.shellSource()
        let progress = try Self.slice(
            source,
            from: "private func progressStage(",
            to: "private func phaseShortName("
        )
        let hero = try Self.slice(
            source,
            from: "private func heroTitle(for phase: Phase)",
            to: "private func statusTitle(for phase: Phase)"
        )
        let status = try Self.slice(
            source,
            from: "private func statusTitle(for phase: Phase)",
            to: "private func phaseShortName("
        )

        #expect(!progress.contains("Experiment One progress"))
        #expect(!progress.contains("REACQUIRE"))
        #expect(progress.contains("Capture progress"))
        #expect(progress.contains("SEAL READY"))
        #expect(progress.contains("MATCH"))

        for leak in ["Evidence, sealed.", "Hold the evidence line.", "Bind the real signal."] {
            #expect(!hero.contains(leak), "Hero copy still exposes evidence/research vocabulary: \(leak)")
        }
        #expect(hero.contains("Capture sealed."))
        #expect(hero.contains("Keep the capture steady."))
        #expect(hero.contains("Confirm the scooter signal."))

        for leak in ["Correlation ambiguous", "Fresh rediscovery", "Correlated target found"] {
            #expect(!status.contains(leak), "Status copy still exposes research vocabulary: \(leak)")
        }
        #expect(status.contains("Multiple signal matches"))
        #expect(status.contains("Checking signal again"))
        #expect(status.contains("Scooter signal matched"))
    }

    @Test("copy cleanup cannot weaken physical or evidence authority")
    func truthAuthorityRemainsPinned() throws {
        let source = try Self.shellSource()

        #expect(source.contains("guard status.physicalProcedurePermitted else"))
        #expect(source.contains("PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)"))
        #expect(source.contains("finalShareIntegrityReport != nil"))
        #expect(source.contains("declaredStationarySetup = nil"))
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
