import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture simulator QA presentation boundary")
struct CaptureSimulatorQAHarnessSourceTests {
    @Test("synthetic harness is DEBUG Simulator only and cannot reach live authority")
    func harnessHasHardCompileAndDependencyBoundary() throws {
        let harness = try readRepositoryFile("NembraApp/App/NembraCaptureSimulatorQAHarness.swift")

        #expect(harness.contains("#if DEBUG && targetEnvironment(simulator)"))
        #expect(harness.contains("enum CaptureSimulatorQAScenario: String, CaseIterable"))
        #expect(harness.hasSuffix("#endif\n"))
        #expect(harness.contains("import Foundation\nimport SwiftUI"))
        #expect(!harness.contains("import NembraBluetoothCapture"))

        let forbiddenLiveSymbols = [
            "CaptureP0Root",
            "SecureLinkView",
            "SecureLinkController",
            "OfficialTuyaAccountAuthorizer",
            "OfficialTuyaDriver",
            "TuyaAccountBridge",
            "OfficialTuyaFactory",
            "CBCentralManager",
            "PassiveBluetoothPowerCycleObservationSession",
            "ExactByteArtifactSeal",
            "NembraCaptureBuildIdentity",
            "NEMBRA_CAPTURE_",
            "NEMBRA_SIMULATION_"
        ]
        for symbol in forbiddenLiveSymbols {
            #expect(!harness.contains(symbol), "synthetic harness references forbidden live symbol: \(symbol)")
        }
    }

    @Test("explicit allow-listed launch argument branches before public root construction")
    func launchRoutingIsExplicitAndFailsClosed() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let harness = try readRepositoryFile("NembraApp/App/NembraCaptureSimulatorQAHarness.swift")

        #expect(app.contains("#if DEBUG && targetEnvironment(simulator)"))
        #expect(app.contains("CaptureSimulatorQALaunch.selection(arguments: ProcessInfo.processInfo.arguments)"))
        #expect(app.contains("case .publicRoot:\n            CaptureP0Root()"))
        #expect(app.contains("case let .scenario(scenario):\n            CaptureSimulatorQAHarness(scenario: scenario)"))
        #expect(app.contains("case let .invalid(rawValue):\n            CaptureSimulatorQAInvalidScenarioView(rawValue: rawValue)"))
        #expect(app.contains("#else\n        CaptureP0Root()\n#endif"))

        #expect(harness.contains("static let argument = \"--nembra-capture-simulator-ui\""))
        #expect(!harness.contains("ProcessInfo.processInfo.environment"))
        #expect(harness.contains("guard !matches.isEmpty else { return .publicRoot }"))
        #expect(harness.contains("guard matches.count == 1 else { return .invalid(\"duplicate scenario argument\") }"))
        #expect(harness.contains("return .invalid(\"missing scenario value\")"))
        #expect(harness.contains("return .invalid(rawValue)"))
    }

    @Test("all synthetic states and obscuring sheets carry unmistakable no-evidence disclosure")
    func disclosureAndNoArtifactBoundaryStayVisible() throws {
        let harness = try readRepositoryFile("NembraApp/App/NembraCaptureSimulatorQAHarness.swift")
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(harness.contains("SIMULATOR QA · SYNTHETIC PRESENTATION · NO BLUETOOTH, TUYA, PHYSICAL OR PROTOCOL EVIDENCE"))
        #expect(harness.contains("nembra.capture.qa.synthetic-disclosure"))
        #expect(harness.contains("nembra.capture.qa.synthetic-sheet-disclosure"))
        #expect(harness.contains("SYNTHETIC UI STATE · NO CAPTURE ARTIFACT"))
        #expect(harness.contains("SYNTHETIC-NO-ARTIFACT-0001"))
        #expect(harness.contains("This finite screen exercises presentation and action routing only."))
        #expect(harness.contains("Text(\"18 / 45 s\")"))
        #expect(harness.contains("ProgressView(value: 18.0 / 45.0)"))
        #expect(harness.contains("requirementRow(\"Repeated scooter data\", ready: false)"))
        #expect(!harness.contains("Text(\"45 / 45 s\")"))
        #expect(app.contains("qaDisclosure: String? = nil"))
        #expect(app.contains("CapturePresentationDisclosureBanner("))

        let forbiddenArtifactMechanisms = [
            "ShareLink",
            "SecureTransfer",
            "ExactByteArtifactSeal",
            "UIActivityViewController",
            "FileManager",
            "Data("
        ]
        for mechanism in forbiddenArtifactMechanisms {
            #expect(!harness.contains(mechanism), "synthetic harness must not create or share artifact bytes: \(mechanism)")
        }
        #expect(harness.contains("CaptureSimulatorQAShareSurrogate"))
        #expect(harness.contains("This sheet checks cancellation and retry routing only. It has no file, bytes, activity controller, or external destination."))
    }

    @Test("finite scenarios and XCUI matrix cover every required primary-flow presentation")
    func scenarioAndUITestMatrixIsComplete() throws {
        let harness = try readRepositoryFile("NembraApp/App/NembraCaptureSimulatorQAHarness.swift")
        let uiTests = try readRepositoryFile("NembraCaptureUITests/NembraCaptureUITests.swift")

        let scenarios = [
            "case safety",
            "correlation-none",
            "correlation-ambiguous",
            "correlation-success",
            "observation-active",
            "observation-timeout",
            "observation-cancelled",
            "integrity-pending",
            "case complete",
            "share-retry"
        ]
        for scenario in scenarios {
            #expect(harness.contains(scenario), "missing finite synthetic scenario: \(scenario)")
        }

        let requiredUITestTokens = [
            "testPublicBuildFailsClosedAndKeepsAccountLinkReachable",
            "testUnknownSyntheticScenarioBlocksInsteadOfOpeningLiveCapture",
            "testSyntheticSafetySheetRepeatsDisclosureAndConfirmationIsFreshLocalState",
            "testSyntheticSafetySheetAtAccessibilityXXXLKeepsDisclosureAndConfirmationReachable",
            "testSyntheticCorrelationWithNoRepeatableTargetStopsWithoutConfirmation",
            "testSyntheticAmbiguousCorrelationStopsWithoutGuessing",
            "testSyntheticSingleCorrelationRequiresConfirmationBeforeObservationPresentation",
            "testSyntheticCorrelationToObservationFitsCompactLandscape",
            "testSyntheticObservationCompletionPresentationStillRequiresIntegrityBeforeComplete",
            "testSyntheticObservationTimeoutIsTerminalAndCannotPresentComplete",
            "testSyntheticStoppingObservationCancelsWithoutAcceptedState",
            "testSyntheticShareCancellationCanRetryTheSamePresentation",
            "-AppleLanguages",
            "-AppleLocale",
            "SYNTHETIC-QA-"
        ]
        for token in requiredUITestTokens {
            #expect(uiTests.contains(token), "missing required XCUI coverage token: \(token)")
        }
        #expect(!uiTests.contains("launchEnvironment"))
    }

    @Test("standalone workflow creates exact iPhone 12 iOS 27 UI runner and preserves synthetic artifacts")
    func workflowUsesDynamicExactSimulatorAndResultBundle() throws {
        let workflow = try readRepositoryFile(".github/workflows/capture-v16-standalone.yml")
        let uiStep = String(try section(
            in: workflow,
            from: "- name: Create exact iPhone 12 / iOS 27 UI-test simulator",
            to: "- name: Upload synthetic Capture UI-test evidence"
        ))

        #expect(workflow.contains("if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository"))
        #expect(occurrences(of: "persist-credentials: false", in: workflow) == 2)
        #expect(workflow.contains("grep -Eq '^Xcode 27([.]|$)'"))
        #expect(uiStep.contains("com.apple.CoreSimulator.SimRuntime.iOS-27"))
        #expect(uiStep.contains("com.apple.CoreSimulator.SimDeviceType.iPhone-12"))
        #expect(uiStep.contains("xcrun simctl create"))
        #expect(uiStep.contains("-destination \"platform=iOS Simulator,id=$SIMULATOR_UDID\""))
        #expect(uiStep.contains("NEMBRA_CAPTURE_BUILD_IDENTIFIER="))
        #expect(uiStep.contains("NEMBRA_CAPTURE_BUILD_COMMIT_SHA="))
        #expect(uiStep.contains("NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256="))
        #expect(uiStep.contains("NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER="))
        #expect(uiStep.contains("-resultBundlePath \"$RESULT_BUNDLE\""))
        #expect(uiStep.contains("xcresulttool export attachments"))
        #expect(!uiStep.contains("CODE_SIGNING_ALLOWED=NO"))
        #expect(!workflow.contains("platform=iOS Simulator,name=iPhone 12,OS=27.0"))
        #expect(workflow.contains("uses: actions/upload-artifact@v6"))
        #expect(workflow.contains("NembraCaptureSyntheticUITests.xcresult"))
    }

    @Test("standalone Xcode target compiles the harness source into Capture only")
    func projectIncludesHarnessOnlyInApplicationSources() throws {
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let appSources = String(try section(
            in: project,
            from: "S10000000000000000000001 /* Sources */ = {",
            to: "S10000000000000000000002 /* Sources */ = {"
        ))
        let uiSources = String(try section(
            in: project,
            from: "S10000000000000000000002 /* Sources */ = {",
            to: "/* End PBXSourcesBuildPhase section */"
        ))

        #expect(project.contains("NembraCaptureSimulatorQAHarness.swift"))
        #expect(appSources.contains("NembraCaptureSimulatorQAHarness.swift in Sources"))
        #expect(!uiSources.contains("NembraCaptureSimulatorQAHarness.swift in Sources"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var remainder = haystack[...]
        while let range = remainder.range(of: needle) {
            count += 1
            remainder = remainder[range.upperBound...]
        }
        return count
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
