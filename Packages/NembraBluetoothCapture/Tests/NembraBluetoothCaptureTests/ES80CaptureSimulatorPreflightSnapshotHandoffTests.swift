import Foundation
import Testing

@Suite("ES80 Capture Simulator preflight authority boundary")
struct ES80CaptureSimulatorPreflightSnapshotHandoffTests {
    private static func captureEntrypointSource() throws -> String {
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
                .appendingPathComponent("NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    private static func captureSimulatorQAHarnessSource() throws -> String {
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
                .appendingPathComponent("NembraCaptureSimulatorQAHarness.swift"),
            encoding: .utf8
        )
    }

    private static func section(
        _ source: String,
        from start: String,
        to end: String
    ) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(
                  of: end,
                  range: startRange.upperBound..<source.endIndex
              ) else {
            throw SourceContractError.expectedSectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private static func suffix(_ source: String, from start: String) throws -> Substring {
        guard let startRange = source.range(of: start) else {
            throw SourceContractError.expectedSectionMissing
        }
        return source[startRange.lowerBound...]
    }

    @Test("Simulator router is explicit, fail-closed, and presentation-only")
    func simulatorRouterCannotMintFieldAuthority() throws {
        let source = try Self.captureEntrypointSource()
        let harness = try Self.captureSimulatorQAHarnessSource()
        let router = try Self.section(
            source,
            from: "@ViewBuilder\n    private var captureRoot: some View {",
            to: "@MainActor\nprivate struct CaptureP0Root"
        )
        let fieldImplementation = try Self.suffix(
            source,
            from: "@MainActor\nprivate struct CaptureP0Root"
        )

        #expect(router.contains("#if DEBUG && targetEnvironment(simulator)"))
        #expect(router.contains("CaptureSimulatorQALaunch.selection(arguments: ProcessInfo.processInfo.arguments)"))
        #expect(router.contains("case .publicRoot:\n            CaptureP0Root()"))
        #expect(router.contains("case let .scenario(scenario):\n            CaptureSimulatorQAHarness(scenario: scenario)"))
        #expect(router.contains("case let .invalid(rawValue):\n            CaptureSimulatorQAInvalidScenarioView(rawValue: rawValue)"))
        #expect(router.contains("#else\n        CaptureP0Root()\n#endif"))

        #expect(harness.contains("guard !matches.isEmpty else { return .publicRoot }"))
        #expect(harness.contains("guard matches.count == 1 else { return .invalid(\"duplicate scenario argument\") }"))
        #expect(harness.contains("return .invalid(\"missing scenario value\")"))
        #expect(harness.contains("return .invalid(rawValue)"))
        #expect(!harness.contains("ProcessInfo.processInfo.environment"))

        let forbiddenSyntheticAuthority = [
            "import NembraBluetoothCapture",
            "SecureLinkView",
            "SecureLinkController",
            "TuyaAccountBridge",
            "OfficialTuyaDriver",
            "PassiveBluetoothPowerCycleObservationSession",
            "TuyaAuthenticatedReadOnlySessionLedger",
            "ExactByteArtifactSeal",
            "PassiveBluetoothExperimentOneSimulatorQAFixture",
            "simulatorQASnapshot",
            "simulatorQAEvidenceLabel"
        ]
        for symbol in forbiddenSyntheticAuthority {
            #expect(!harness.contains(symbol), "Simulator presentation references live authority: \(symbol)")
        }

        #expect(!fieldImplementation.contains("CaptureSimulatorQALaunch"))
        #expect(!fieldImplementation.contains("CaptureSimulatorQAHarness("))
        #expect(!fieldImplementation.contains("CaptureSimulatorQAInvalidScenarioView"))
    }

    @Test("field correlation is minted by fresh package-owned power-cycle observations")
    func correlationRequiresFreshPackageOwnedObservationAuthority() throws {
        let source = try Self.captureEntrypointSource()

        #expect(source.contains("correlationSession = try PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)"))
        #expect(source.contains("try session.startCurrentWindow()"))
        #expect(source.contains("let final = try session.finishCurrentWindow()"))
        #expect(source.contains("correlationProvenance = CorrelationProvenance(result: result)"))
        #expect(source.contains("candidate.freshlyCorrelated"))
        #expect(source.contains("targetCorrelationOperatorConfirmed = true"))
    }

    @Test("canonical acceptance comes from authenticated ledger evidence and an immutable seal")
    func acceptedCaptureCannotBeMintedFromSyntheticSnapshotState() throws {
        let source = try Self.captureEntrypointSource()

        #expect(source.contains("TuyaAuthenticatedReadOnlyPreflight.verdict(for: ledgerSnapshot)"))
        #expect(source.contains("sessionLedger.captureApplicationDelivery("))
        #expect(source.contains("try await sessionLedger.recordApplicationUpdate("))
        #expect(source.contains("receipt: receipt"))
        #expect(source.contains("sessionLedger.captureLivenessReceipt(for: token)"))
        #expect(source.contains("try await self.sessionLedger.observeCurrentConnection("))
        #expect(source.contains("receipt: livenessReceipt"))
        #expect(source.contains("try await sessionLedger.sealAcceptedObservation(for: token)"))
        #expect(source.contains("self.sealedAcceptedExport = self.makeExport("))
        #expect(source.contains("self.phase = .accepted"))
        #expect(!source.contains("simulatorQASnapshot"))
    }

    private enum SourceContractError: Error {
        case expectedSectionMissing
    }
}
