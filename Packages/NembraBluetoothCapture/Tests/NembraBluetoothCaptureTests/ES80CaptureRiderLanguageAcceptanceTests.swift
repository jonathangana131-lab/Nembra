import Foundation
import Testing

@Suite("ES80 Capture rider-language acceptance")
struct ES80CaptureRiderLanguageAcceptanceTests {
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

    private static func riderSurface(in source: String) throws -> Substring {
        let beginning = try #require(source.range(of: "private func hero(for phase: Phase)"))
        let details = try #require(
            source.range(
                of: "private var captureDetailsSheet",
                range: beginning.lowerBound..<source.endIndex
            )
        )
        return source[beginning.lowerBound..<details.lowerBound]
    }

    private static func phaseSurface(in source: String) throws -> Substring {
        let beginning = try #require(source.range(of: "private func phase("))
        let end = try #require(
            source.range(
                of: "private var presentationAnalysisReady",
                range: beginning.lowerBound..<source.endIndex
            )
        )
        return source[beginning.lowerBound..<end.lowerBound]
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

    @Test("failure and recovery states stay rider-readable")
    func failureStatesStayHumanFirst() throws {
        let source = try Self.shellSource()
        let phaseSurface = try Self.phaseSurface(in: source)

        let engineeringPhrasesThatMustStayOutOfFailureCopy = [
            "evidence life",
            "consumed authority",
            "package-owned CoreBluetooth controller",
            "package-issued observation authority",
            "package-owned Experiment One workflow"
        ]

        for phrase in engineeringPhrasesThatMustStayOutOfFailureCopy {
            #expect(
                !phaseSurface.contains(phrase),
                "Primary failure/recovery copy still exposes engineering vocabulary: \(phrase)"
            )
        }

        #expect(phaseSurface.contains("This capture cannot safely continue"))
        #expect(phaseSurface.contains("Bluetooth capture is unavailable in this build"))
        #expect(phaseSurface.contains("Start again from OFF 1"))
        #expect(phaseSurface.contains("Simulator QA interruption fixture"))
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
