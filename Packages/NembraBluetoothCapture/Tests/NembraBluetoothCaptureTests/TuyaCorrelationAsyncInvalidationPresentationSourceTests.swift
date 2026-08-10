import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlation asynchronous invalidation presentation")
struct TuyaCorrelationAsyncInvalidationPresentationSourceTests {
    @Test("package invalidation is consumed by the app lifecycle and exits the dead scan phase")
    func invalidatedCorrelationSeriesHasAnAppRecoveryConsumer() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(
            in: app,
            from: "private final class SecureLinkController",
            to: "private protocol OfficialTuyaDriver"
        )
        let consumer = try section(
            in: String(controller),
            from: "func consumeCorrelationAsyncInvalidationIfNeeded()",
            to: "var correlationWindowLabel"
        )
        let body = String(consumer)

        #expect(body.contains("phase == .baseline || phase == .scanning"))
        #expect(body.contains("correlationProgress?.isSeriesInvalidated == true"))
        #expect(body.contains("failLocally("))
        #expect(body.contains("target_correlation_async_invalidated"))
        #expect(!body.contains("Task.sleep"), Comment(rawValue: "Recovery must consume the existing package terminal, not create another polling clock."))
    }

    @Test("the existing TimelineView presentation clock invokes the lifecycle consumer")
    func timelineRefreshDrivesTerminalConsumptionWithoutSecondScannerClock() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = try section(in: app, from: "private struct SecureLinkView", to: "#Preview")
        let body = String(view)

        #expect(body.contains("TimelineView(.periodic(from: .now, by: 0.5))"))
        #expect(body.contains(".onChange(of: test.correlationProgress?.isSeriesInvalidated == true)"))
        #expect(body.contains("test.consumeCorrelationAsyncInvalidationIfNeeded()"))
        #expect(!body.contains("correlationProgressObserver"))
        #expect(!body.contains("Task.sleep(for: .milliseconds(100))"))
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
