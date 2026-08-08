import Foundation
import Testing

@Suite("ES80 Capture primary helper copy")
struct ES80CapturePrimaryHelperCopyTests {
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

    @Test("rendered helper paths cannot reintroduce known engineering copy")
    func helperPathsStayHumanFirst() throws {
        let source = try Self.shellSource()
        let forbidden = [
            "FIELD AUTHORITY",
            "Learning the readable surface",
            "Freezing final evidence",
            "final evidence cutoff",
            "replaying consumed authority",
            "scan-liveness",
            "fresh package-owned Experiment One workflow",
            "String(describing: error)",
            "case .complete: return \"Evidence, sealed.\"",
            "case .readyToSeal, .observing: return \"Hold the evidence line.\"",
            "return \"Bind the real signal.\"",
            "return \"Find the real scooter signal.\""
        ]

        for fragment in forbidden {
            #expect(
                !source.contains(fragment),
                "Rendered primary/helper copy still exposes implementation vocabulary: \(fragment)"
            )
        }

        #expect(source.contains("CAPTURE LOCKED"))
        #expect(source.contains("This build is not ready for a field capture"))
        #expect(source.contains("Reading available data"))
        #expect(source.contains("case .complete: return \"Capture, sealed.\""))
        #expect(source.contains("case .readyToSeal, .observing: return \"Keep it steady.\""))
        #expect(source.contains("return \"Stay with this signal.\""))
        #expect(source.contains("return \"Find the scooter signal.\""))
    }

    @Test("stationary preflight hides engineering recipe token without weakening charger gate")
    func preflightStaysHumanFirstAndMechanical() throws {
        let source = try Self.appSource()
        let beginning = try #require(
            source.range(of: "private struct ES80ExperimentOneStationaryPreflightView")
        )
        let end = try #require(
            source.range(
                of: "private struct ES80ExperimentOneFieldNoGoView",
                range: beginning.lowerBound..<source.endIndex
            )
        )
        let preflight = source[beginning.lowerBound..<end.lowerBound]

        #expect(!preflight.contains("ES80-FINGERPRINT-v1"))
        #expect(preflight.contains("Required for this capture"))
        #expect(preflight.contains("Disconnected"))
        #expect(preflight.contains("Connected"))
        #expect(preflight.contains("Disconnect charger to continue"))
        #expect(preflight.contains("Nembra cannot sense the charger directly"))
        #expect(preflight.contains("PassiveBluetoothStationaryCaptureChargerState.disconnected.rawValue"))
        #expect(preflight.contains(".disabled(!canContinue)"))
        #expect(preflight.contains("selectedChargerState = nil"))
        #expect(preflight.contains("disconnectedDeclarationAccepted = false"))
        #expect(source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure"))
    }

    @Test("technical truth and final-share authority remain behind the product copy")
    func truthContractsRemainAvailable() throws {
        let source = try Self.shellSource()

        #expect(source.contains("guard status.physicalProcedurePermitted else"))
        #expect(source.contains("PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)"))
        #expect(source.contains("finalShareIntegrityReport != nil"))
        #expect(source.contains("PASSIVE / READ ONLY"))
        #expect(source.contains("Share Capture"))
        #expect(source.contains("View Details"))

        let detailsStart = try #require(source.range(of: "private var captureDetailsSheet"))
        let details = source[detailsStart.lowerBound..<source.endIndex]
        #expect(details.contains("Truth boundary"))
        #expect(details.contains("CoreBluetooth"))
        #expect(details.contains("Software Export SHA-256"))
        #expect(details.contains("Runtime executable SHA-256"))
        #expect(details.contains("does not authenticate the physical ES80"))
    }
}
