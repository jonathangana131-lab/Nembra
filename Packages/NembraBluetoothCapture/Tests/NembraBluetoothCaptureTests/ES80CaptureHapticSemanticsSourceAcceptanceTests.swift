import Foundation
import Testing

@Suite("ES80 Capture haptic semantics source acceptance")
struct ES80CaptureHapticSemanticsSourceAcceptanceTests {
    private func shellSource() throws -> String {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = thisFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NembraBluetoothCapture
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root marker
        let shell = repositoryRoot
            .appendingPathComponent("NembraApp/Features/Research/ES80CaptureShellView.swift")
        return try String(contentsOf: shell, encoding: .utf8)
    }

    @Test("Capture milestones provide deliberate event-driven haptic semantics")
    func semanticMilestonesUseHapticsWithoutPolling() throws {
        let source = try shellSource()

        #expect(source.contains("sensoryFeedback"), Comment("EXPECTED RED: Capture currently has no deliberate SwiftUI sensory feedback on its major rider-facing milestones."))
        #expect(source.contains(".success"), Comment("Accepted completion/analysis readiness should have one restrained success tactile cue."))
        #expect(
            source.contains(".warning") || source.contains(".error"),
            Comment("A blocking capture-stop/restart-required transition should have one restrained warning/error tactile cue.")
        )

        // Haptic triggers must represent semantic state transitions, never the 0.5 s presentation clock
        // or the display-only countdown values. This keeps tactile output sparse and truthful.
        let feedbackLines = source
            .split(separator: "\n")
            .filter { $0.contains("sensoryFeedback") }
            .map(String.init)
            .joined(separator: "\n")
        #expect(!feedbackLines.contains("TimelineView"))
        #expect(!feedbackLines.contains("remaining"))
        #expect(!feedbackLines.contains("nowUptimeNanoseconds"))
    }

    @Test("Haptics stay presentation-only and cannot become Capture authority")
    func hapticsDoNotChangeAuthority() throws {
        let source = try shellSource()

        #expect(source.contains("PassiveBluetoothExperimentOneCoordinator"))
        #expect(source.contains("physicalProcedurePermitted"))
        #expect(source.contains("presentationAnalysisReady"))

        // This contract intentionally asks only for SwiftUI sensory feedback. A tactile cue must
        // never be used as a gate, evidence receipt, Bluetooth action, or physical authorization.
        #expect(!source.contains("sensoryFeedbackPermitsPhysicalProcedure"))
        #expect(!source.contains("hapticAuthorization"))
        #expect(!source.contains("hapticEvidence"))
    }
}
