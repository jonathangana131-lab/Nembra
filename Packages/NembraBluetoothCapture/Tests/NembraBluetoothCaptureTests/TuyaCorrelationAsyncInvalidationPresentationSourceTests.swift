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

        #expect(controller.contains("var correlationSeriesIsInvalidated: Bool"))
        #expect(controller.contains("session.progress?.isSeriesInvalidated == true"))
        #expect(controller.contains("target_correlation_async_invalidated"))
        #expect(controller.contains("func consumeAsynchronousCorrelationInvalidation()"))
    }

    @Test("existing TimelineView consumes the terminal without a second polling clock")
    func timelineRefreshDrivesLifecycleRecovery() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = try section(in: app, from: "private struct SecureLinkView", to: "private struct SecureTransfer")

        #expect(view.contains("TimelineView(.periodic"))
        #expect(view.contains(".onChange(of: test.correlationSeriesIsInvalidated)"))
        #expect(view.contains("test.consumeAsynchronousCorrelationInvalidation()"))
        #expect(!view.contains("correlationInvalidationTask"))
        #expect(!view.contains("Task.sleep(for: .milliseconds(100))"))
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
