import Foundation
import Testing

@Suite("ES80 Capture accessibility source acceptance")
struct ES80CaptureAccessibilitySourceAcceptanceTests {
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

    @Test("Capture does not require custom spatial motion or transparency effects")
    func captureHasNoCustomMotionOrTransparencyDependency() throws {
        let source = try Self.shellSource()

        // Capture is a measurement instrument. Its accepted state must remain readable when system
        // motion/transparency accommodations are enabled, so the production shell deliberately does
        // not depend on bespoke animation, blur, material, or glass effects to communicate state.
        let forbiddenPresentationDependencies = [
            "withAnimation",
            ".animation(",
            ".blur(",
            ".ultraThinMaterial",
            ".thinMaterial",
            ".regularMaterial",
            ".thickMaterial",
            ".ultraThickMaterial",
            ".glassEffect("
        ]

        for dependency in forbiddenPresentationDependencies {
            #expect(
                !source.contains(dependency),
                "Capture gained a custom motion/transparency dependency that needs explicit accessibility treatment: \(dependency)"
            )
        }

        #expect(source.contains(".background(Color.black.ignoresSafeArea())"))
        #expect(source.contains(".foregroundStyle(.white)"))
    }

    @Test("high-frequency presentation collapses decorative children into stable rider semantics")
    func pollingPresentationDoesNotExposeEveryChildAsAnAccessibilityElement() throws {
        let source = try Self.shellSource()

        #expect(source.contains("TimelineView(.periodic("))
        #expect(source.contains("static let statusPollInterval: TimeInterval = 0.5"))

        // The six-segment rail changes with package state but must be one semantic progress element,
        // not six independently focusable visual segments plus duplicate labels.
        let progressStart = try #require(source.range(of: "private func progressRail("))
        let progressEnd = try #require(
            source.range(
                of: "private func primaryContent(",
                range: progressStart.lowerBound..<source.endIndex
            )
        )
        let progressSource = source[progressStart.lowerBound..<progressEnd.lowerBound]
        #expect(progressSource.contains(".accessibilityElement(children: .ignore)"))
        #expect(progressSource.contains("progressAccessibilityLabel("))
        #expect(progressSource.contains(".accessibilityIdentifier(\"es80.capture.experiment-progress\")"))

        // The live OFF/ON observation card similarly supplies one label/value/hint rather than
        // exposing its changing visual children individually. VoiceOver is part of the primary rider
        // surface, so it must not fall back to protocol/acquisition vocabulary hidden from sighted copy.
        let primaryStart = try #require(source.range(of: "private func primaryContent("))
        let primaryEnd = try #require(
            source.range(
                of: "private func correlationReadyPanel(",
                range: primaryStart.lowerBound..<source.endIndex
            )
        )
        let primarySource = source[primaryStart.lowerBound..<primaryEnd.lowerBound]
        #expect(primarySource.contains("case let .correlationObserving(window):"))
        #expect(primarySource.contains(".accessibilityElement(children: .ignore)"))
        #expect(primarySource.contains(".accessibilityLabel(\"\\(phaseShortName(window)) observation\")"))
        #expect(primarySource.contains(".accessibilityHint("))

        let implementationTermsThatMustStayOutOfPrimaryVoiceOver = [
            "bounded Bluetooth observation window",
            "Bluetooth observation",
            "CoreBluetooth",
            "finite acquisition",
            "package-owned"
        ]
        for term in implementationTermsThatMustStayOutOfPrimaryVoiceOver {
            #expect(
                !primarySource.contains(term),
                "Primary VoiceOver copy still exposes implementation vocabulary: \(term)"
            )
        }
    }

    @Test("accessibility semantics remain presentation-only and cannot mint evidence")
    func accessibilityLayerDoesNotBecomeCaptureAuthority() throws {
        let source = try Self.shellSource()

        #expect(source.contains("static let requiredObservationGuidanceNanoseconds: UInt64 = 60_000_000_000"))
        #expect(source.contains("The displayed timer is guidance only."))
        #expect(source.contains("Display guidance complete; waiting for seal readiness"))
        #expect(source.contains("Available only after Nembra verifies the required observation time."))

        // The view may request package operations, but accessibility modifiers and the 0.5-second
        // presentation clock must never call recorder/evidence constructors directly.
        let bodyStart = try #require(source.range(of: "var body: some View"))
        let shellBody = source[bodyStart.lowerBound..<source.endIndex]
        #expect(!shellBody.contains("PassiveBluetoothCaptureRecorder("))
        #expect(!shellBody.contains("PassiveBluetoothCaptureEvent("))
        #expect(!shellBody.contains("PassiveBluetoothCaptureArtifact("))
    }
}
