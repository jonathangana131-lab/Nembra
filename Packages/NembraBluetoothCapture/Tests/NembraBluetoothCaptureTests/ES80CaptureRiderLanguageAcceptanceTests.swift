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
        let beginning = try #require(source.range(of: "private var passiveSafetyPanel"))
        let details = try #require(
            source.range(
                of: "private var captureDetailsSheet",
                range: beginning.lowerBound..<source.endIndex
            )
        )
        return source[beginning.lowerBound..<details.lowerBound]
    }

    /// `phase(...)`, the coordinator-error mapper, and Bluetooth-state mapper live below Details in
    /// source order, but their returned strings are rendered back into the primary rider surface.
    /// Keep that dynamic copy in the rider-language acceptance boundary instead of accidentally
    /// treating source-file location as UI hierarchy.
    private static func riderDynamicCopy(in source: String) throws -> Substring {
        let beginning = try #require(source.range(of: "private func phase("))
        let end = try #require(
            source.range(
                of: "private func statePanel(",
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
            "selectable full Bluetooth identifier",
            "post-admission scan",
            "fresh scan epoch created after the sealed admission",
            "package-owned correlated target",
            "finite acquisition",
            "Finite acquisition",
            "accepted Horizon authority",
            "accepted monotonic observation interval",
            "package-owned Ready epoch",
            "committing Horizon",
            "immutable JSON artifact",
            "Evidence failed closed",
            "bounded CoreBluetooth advertisement catalog",
            "package-owned outer, SoftwareExport, and immutable Capture integrity checks",
            "application characteristic-value writes",
            "package producer",
            "HORIZON READY",
            "healthItem(\"FINITE\"",
            "healthItem(\"HORIZON\""
        ]

        for phrase in engineeringPhrasesThatMustStayOutOfPrimaryCopy {
            #expect(
                !riderSurface.contains(phrase),
                "Primary Capture copy still exposes engineering vocabulary: \(phrase)"
            )
        }

        // The persistent read-only badge sits above `passiveSafetyPanel`, so validate it against
        // the full shell rather than accidentally requiring it to be duplicated in every state.
        #expect(source.contains("PASSIVE / READ ONLY"))
        #expect(riderSurface.contains("Scooter OFF"))
        #expect(riderSurface.contains("Scooter ON"))
        #expect(riderSurface.contains("Share Capture"))
        #expect(riderSurface.contains("View Details"))
        #expect(riderSurface.contains("DISCOVERY"))
        #expect(riderSurface.contains("SEAL"))
    }

    @Test("dynamic failure and recovery copy is rider-facing even when helpers live below Details")
    func dynamicPrimaryCopyStaysHumanFirst() throws {
        let source = try Self.shellSource()
        let dynamicCopy = try Self.riderDynamicCopy(in: source)

        let implementationPhrasesThatMustNotReachDynamicPrimaryCopy = [
            "evidence life",
            "capture authority",
            "consumed authority",
            "package-owned CoreBluetooth controller",
            "package-issued observation authority",
            "package-owned Experiment One workflow",
            "fresh package-owned Experiment One workflow",
            "bounded startup interval",
            "local observation-window sequence"
        ]

        for phrase in implementationPhrasesThatMustNotReachDynamicPrimaryCopy {
            #expect(
                !dynamicCopy.contains(phrase),
                "Dynamic Capture copy still exposes implementation vocabulary: \(phrase)"
            )
        }

        #expect(dynamicCopy.contains("start a fresh Experiment One"))
        #expect(dynamicCopy.contains("Passive Bluetooth capture is unavailable"))
        #expect(dynamicCopy.contains("Restart from OFF 1") || dynamicCopy.contains("restart from OFF 1"))
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
