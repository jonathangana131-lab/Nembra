import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlation asynchronous invalidation presentation")
struct TuyaCorrelationAsyncInvalidationPresentationSourceTests {
    @Test("asynchronous package invalidation cannot leave the field flow trapped in a scan phase")
    func invalidatedCorrelationSeriesHasAnAppRecoveryConsumer() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(
            in: app,
            from: "private final class SecureLinkController",
            to: "private protocol OfficialTuyaDriver"
        )

        #expect(controller.contains("isSeriesInvalidated"), Comment(rawValue: "The package exposes asynchronous terminal invalidation in correlation progress, but the app never consumes it."))
        #expect(controller.contains("target_correlation_async_invalidated"), Comment(rawValue: "The app needs a durable fail-closed/restart outcome for scanner timeout or Bluetooth loss that occurs without a button press."))
    }

    @Test("periodic presentation refresh alone is not treated as lifecycle recovery")
    func timelineRefreshDoesNotSubstituteForTerminalStateTransition() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = try section(
            in: app,
            from: "private struct SecureLinkView",
            to: "private struct SecureTransfer"
        )
        let controller = try section(
            in: app,
            from: "private final class SecureLinkController",
            to: "private protocol OfficialTuyaDriver"
        )

        #expect(view.contains("TimelineView(.periodic"))
        #expect(controller.contains("var correlationProgress: PassiveBluetoothPowerCycleObservationProgress?"))
        #expect(controller.contains("isSeriesInvalidated"), Comment(rawValue: "TimelineView can repaint package progress, but repainting a terminal invalidation does not move phase out of baseline/scanning or provide restart authority."))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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
