import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlation asynchronous invalidation presentation")
struct TuyaCorrelationAsyncInvalidationPresentationSourceTests {
    @Test("package terminal invalidation moves the app to an explicit restart-capable failure")
    func invalidatedCorrelationSeriesHasAnAppRecoveryConsumer() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(
            in: app,
            from: "private final class SecureLinkController",
            to: "private protocol OfficialTuyaDriver"
        )

        #expect(controller.contains("var correlationSeriesIsInvalidated: Bool { correlationProgress?.isSeriesInvalidated == true }"))
        #expect(controller.contains("func reconcileCorrelationLifecycle()"))
        #expect(controller.contains("correlationSession = nil"))
        #expect(controller.contains("phase = .failed"))
        #expect(controller.contains("target_correlation_async_invalidated"))
        #expect(controller.contains("no target evidence was promoted"))
    }

    @Test("periodic presentation consumes the package terminal instead of only repainting it")
    func timelineRefreshDrivesTheLifecycleMirror() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = try section(
            in: app,
            from: "private struct SecureLinkView",
            to: "private struct SecureTransfer"
        )

        #expect(view.contains("TimelineView(.periodic"))
        #expect(view.contains(".onChange(of: test.correlationSeriesIsInvalidated)"))
        #expect(view.contains("test.reconcileCorrelationLifecycle()"))
    }

    @Test("reconciliation stays presentation-only and idempotent after the package terminal")
    func recoveryDoesNotMintCorrelationAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let method = try section(
            in: app,
            from: "func reconcileCorrelationLifecycle()",
            to: "var correlationWindowLabel"
        )

        #expect(method.contains("guard phase == .baseline || phase == .scanning"))
        #expect(method.contains("correlationSeriesIsInvalidated else { return }"))
        #expect(method.contains("correlationSession = nil"))
        #expect(method.contains("pendingCorrelatedTargetID = nil"))
        #expect(method.contains("phase = .failed"))
        #expect(!method.contains("finishCurrentWindow"))
        #expect(!method.contains("finishCorrelationSeries"))
        #expect(!method.contains("Candidate("))
        #expect(!method.contains("recordApplicationUpdate"))
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
