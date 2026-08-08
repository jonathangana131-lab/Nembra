import Foundation
import Testing

@Suite("ES80 Capture VoiceOver alert acceptance")
struct ES80CaptureVoiceOverAlertAcceptanceTests {
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

    private static func span(in source: String, from startMarker: String, to endMarker: String) throws -> Substring {
        let start = try #require(source.range(of: startMarker))
        let end = try #require(source.range(of: endMarker, range: start.lowerBound..<source.endIndex))
        return source[start.lowerBound..<end.lowerBound]
    }

    @Test("blocking announcements are event-driven instead of coupled to the two-hertz render clock")
    func announcementsStayOffTheDisplayClock() throws {
        let source = try Self.shellSource()
        let timeline = try Self.span(in: source, from: "TimelineView(.periodic", to: "private func hero")
        #expect(timeline.contains(".onChange(of: currentPhase)"))
        #expect(timeline.contains("announceAccessibilityStatus(newPhase)"))
        #expect(timeline.contains(".onChange(of: diagnosticMessage)"))
        #expect(timeline.contains(".onChange(of: sharePreparationWarning)"))
        #expect(timeline.contains(".onChange(of: presentationAnalysisReady)"))
        #expect(timeline.contains("guard isReady, currentPhase == .complete else { return }"))
        #expect(!timeline.contains("UIAccessibility.post"))
    }

    @Test("VoiceOver speaks blocking and newly actionable states but not telemetry cadence")
    func statusAnnouncementsStaySparseAndActionable() throws {
        let source = try Self.shellSource()
        let status = try Self.span(in: source, from: "private func announceAccessibilityStatus", to: "private func announceAccessibilityAlert")
        #expect(status.contains("guard UIAccessibility.isVoiceOverRunning else { return }"))
        #expect(status.contains("case let .bluetoothUnavailable(message):"))
        #expect(status.contains("case let .correlationFailed(message):"))
        #expect(status.contains("case .noRepeatableTarget:"))
        #expect(status.contains("case let .ambiguousTargets(count):"))
        #expect(status.contains("case .readyToSeal:"))
        #expect(status.contains("Seal Capture is now available."))
        #expect(status.contains("case .complete:"))
        #expect(status.contains("case let .failed(message):"))
        #expect(status.contains("UIAccessibility.post(notification: .announcement"))
        #expect(!status.contains("case .observing:"))
        #expect(!status.contains("case .correlationObserving"))
        #expect(!status.contains("seconds of display guidance remaining"))
    }

    @Test("analysis readiness is announced when final Share verification completes after sealing")
    func analysisReadyTransitionIsNotLost() throws {
        let source = try Self.shellSource()
        let timeline = try Self.span(in: source, from: "TimelineView(.periodic", to: "private func hero")
        #expect(timeline.contains(".onChange(of: presentationAnalysisReady)"))
        #expect(timeline.contains("guard isReady, currentPhase == .complete else { return }"))
        #expect(timeline.contains("announceAccessibilityAlert(\"Capture complete. Ready for analysis and sharing.\")"))
    }

    @Test("async warning banners are coherent accessibility elements and announce only when VoiceOver runs")
    func warningBannerSemanticsStayCoherent() throws {
        let source = try Self.shellSource()
        let banner = try Self.span(in: source, from: "private func diagnosticBanner", to: "private func announceAccessibilityStatus")
        let alert = try Self.span(in: source, from: "private func announceAccessibilityAlert", to: "private func guidanceFootnote")
        #expect(banner.contains(".accessibilityElement(children: .ignore)"))
        #expect(banner.contains(".accessibilityLabel(\"Capture alert\")"))
        #expect(banner.contains(".accessibilityValue(message)"))
        #expect(alert.contains("UIAccessibility.isVoiceOverRunning"))
        #expect(alert.contains("!message.isEmpty"))
        #expect(alert.contains("notification: .announcement"))
        #expect(alert.contains("Capture alert."))
    }

    @Test("announcement presentation cannot weaken Capture authority")
    func authorityBoundaryRemainsUntouched() throws {
        let source = try Self.shellSource()
        #expect(source.contains("guard status.physicalProcedurePermitted else"))
        #expect(source.contains("coordinator.confirmCorrelatedTargetAndBeginRediscovery()"))
        #expect(source.contains("coordinator.finalizeObservationHorizon()"))
        #expect(source.contains("PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)"))
    }
}
