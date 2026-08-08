import Foundation
import Testing

@Suite("ES80 Capture primary and progress rider language")
struct ES80CapturePrimaryProgressRiderLanguageAcceptanceTests {
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

    @Test("primary cards use field language instead of research vocabulary")
    func primaryCardsStayHumanFirst() throws {
        let source = try Self.shellSource()

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
            #expect(!source.contains(leak), "Primary Capture copy still exposes research vocabulary: \(leak)")
        }

        #expect(source.contains("CAPTURE PROGRESS"))
        #expect(source.contains("CAPTURE LOCKED"))
        #expect(source.contains("Begin OFF 1 check"))
        #expect(source.contains("Confirm scooter signal"))
        #expect(source.contains("READ-ONLY CONNECTION"))
        #expect(source.contains("READ-ONLY DISCOVERY"))
        #expect(source.contains("READY TO SEAL"))
        #expect(source.contains("healthItem(\"SIGNAL\""))
        #expect(source.contains("healthItem(\"DISCOVERY\""))
        #expect(source.contains("healthItem(\"SEAL\""))
    }

    @Test("remaining field, ready, completion, and error copy avoids research jargon")
    func remainingRiderCopyStaysHumanFirst() throws {
        let source = try Self.shellSource()

        for leak in [
            "OFF / ON windows, connection, capture, and sealing",
            "bounded observation window",
            "target matching and passive capture",
            "Begin passive observation",
            "Verify final artifact",
            "Field procedure locked"
        ] {
            #expect(!source.contains(leak), "Primary Capture copy still exposes research vocabulary: \(leak)")
        }

        #expect(source.contains("OFF / ON checks, connection, capture, and sealing"))
        #expect(source.contains("then begin this Bluetooth check."))
        #expect(source.contains("signal matching and read-only capture"))
        #expect(source.contains("Begin read-only observation"))
        #expect(source.contains("Verify Capture file"))
        #expect(source.contains("CAPTURE LOCKED"))

        #expect(!source.contains("This OFF / ON series has an evidence gap."))
        #expect(source.contains("These OFF / ON checks were interrupted. Start a fresh capture."))
    }

    @Test("progress, hero, and status language stays rider-first")
    func progressAndStatusStayHumanFirst() throws {
        let source = try Self.shellSource()

        #expect(!source.contains("Experiment One progress"))
        #expect(!source.contains("REACQUIRE"))
        #expect(source.contains("Capture progress"))
        #expect(source.contains("SEAL READY"))
        #expect(source.contains("MATCH"))

        for leak in ["Evidence, sealed.", "Hold the evidence line.", "Bind the real signal."] {
            #expect(!source.contains(leak), "Hero copy still exposes evidence/research vocabulary: \(leak)")
        }
        #expect(source.contains("Capture sealed."))
        #expect(source.contains("Keep the capture steady."))
        #expect(source.contains("Confirm the scooter signal."))

        for leak in ["Correlation ambiguous", "Fresh rediscovery", "Correlated target found"] {
            #expect(!source.contains(leak), "Status copy still exposes research vocabulary: \(leak)")
        }
        #expect(source.contains("Multiple signal matches"))
        #expect(source.contains("Checking signal again"))
        #expect(source.contains("Scooter signal matched"))
    }

    @Test("post-seal cleanup recovery remains actionable")
    func postSealCleanupCopyIsHumanFirst() throws {
        let source = try Self.shellSource()

        #expect(!source.contains("post-seal Bluetooth cleanup"))
        #expect(source.contains("The Capture is sealed, but Bluetooth cleanup did not finish."))
        #expect(source.contains("restart Nembra before starting another one"))
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
