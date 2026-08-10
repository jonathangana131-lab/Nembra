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
        #expect(controller.contains("isSeriesInvalidated"))
        #expect(controller.contains("consumeCorrelationAsyncInvalidationIfNeeded"))
        #expect(controller.contains("target_correlation_async_invalidated"))
    }

    @Test("existing TimelineView clock consumes the package terminal without a second polling task")
    func timelineRefreshDrivesTerminalStateTransition() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = try section(in: app, from: "private struct SecureLinkView", to: "private struct SecureTransfer")
        let body = String(view)
        #expect(body.contains("TimelineView(.periodic(from: .now, by: 0.5))"))
        #expect(body.contains(".onChange(of: test.correlationSeriesIsInvalidated"))
        #expect(body.contains("test.consumeCorrelationAsyncInvalidationIfNeeded()"))
        #expect(!body.contains("correlationProgressTask"))
        #expect(!body.contains("Task.sleep(for: .milliseconds(100))"))
    }

    @Test("terminal consumer is evidence-neutral and releases only invalid correlation authority")
    func terminalConsumerDoesNotManufactureVehicleEvidence() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let function = try sourceFunction(in: app, marker: "func consumeCorrelationAsyncInvalidationIfNeeded()")
        #expect(function.contains("correlationSeriesIsInvalidated"))
        #expect(function.contains("correlationSession = nil"))
        #expect(function.contains("phase = .failed"))
        #expect(function.contains("target_correlation_async_invalidated"))
        #expect(!function.contains("markAuthenticated(for:"))
        #expect(!function.contains("recordApplicationUpdate"))
        #expect(!function.contains("endConnection(for:"))
        #expect(!function.contains("scanForPeripherals"))
        #expect(!function.contains("connect("))
    }

    private func sourceFunction(in source: String, marker: String) throws -> Substring {
        guard let markerRange = source.range(of: marker),
              let openingBrace = source[markerRange.upperBound...].firstIndex(of: "{") else {
            Issue.record("Expected source function missing: \(marker)")
            throw SourceContractError.sectionMissing
        }
        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return source[markerRange.lowerBound...index] }
            default: break
            }
            index = source.index(after: index)
        }
        Issue.record("Expected balanced source function body: \(marker)")
        throw SourceContractError.sectionMissing
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

    private enum SourceContractError: Error { case sectionMissing }
}
