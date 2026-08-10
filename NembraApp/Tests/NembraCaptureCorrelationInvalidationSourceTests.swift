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

        #expect(controller.contains("func consumeCorrelationInvalidationIfNeeded()"))
        #expect(controller.contains("packageProgress.isSeriesInvalidated"))
        #expect(controller.contains("target_correlation_async_invalidated"))
        #expect(controller.contains("failLocally("))
        #expect(controller.contains("Restart the complete OFF1→ON1→OFF2→ON2 series from OFF1"))
    }

    @Test("existing periodic presentation surfaces the terminal without a second polling authority")
    func timelineRefreshDrivesTerminalStateTransition() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = try section(in: app, from: "private struct SecureLinkView", to: "private struct SecureTransfer")

        #expect(view.contains("TimelineView(.periodic"))
        #expect(view.contains("onChange(of: test.correlationProgress?.isSeriesInvalidated)"))
        #expect(view.contains("test.consumeCorrelationInvalidationIfNeeded()"))
        #expect(!view.contains("Task.sleep"))
        #expect(!view.contains("Timer.publish"))
    }

    @Test("failed phase exposes a clean OFF1 restart action")
    func failedPhaseReturnsOperatorToFreshSeriesStart() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let discovery = try section(in: app, from: "private var discoveryCard", to: "private func authenticationCard")

        #expect(discovery.contains("case .idle, .failed:"))
        #expect(discovery.contains("Button(\"Start OFF1 correlation\") { test.startBaseline() }"))
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
