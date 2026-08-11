import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlation asynchronous invalidation presentation")
struct TuyaCorrelationAsyncInvalidationPresentationSourceTests {
    @Test("asynchronous package invalidation leaves scan phase through existing presentation clock")
    func invalidatedCorrelationSeriesHasARecoveryConsumer() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(
            in: app,
            from: "private final class SecureLinkController",
            to: "private protocol OfficialTuyaDriver"
        )
        let view = try section(
            in: app,
            from: "private struct SecureLinkView",
            to: "private struct SecureTransfer"
        )

        #expect(controller.contains("isSeriesInvalidated"))
        #expect(controller.contains("target_correlation_async_invalidated"))
        #expect(controller.contains("consumeCorrelationAsyncInvalidation"))
        #expect(controller.contains("correlationSession = nil"))

        // Recovery must consume the package terminal using the already-existing periodic
        // presentation path. Do not add a second scanner or a blind 10 Hz polling task.
        #expect(view.contains("TimelineView(.periodic(from: .now, by: 0.5))"))
        #expect(view.contains(".onChange(of: test.correlationProgress?.isSeriesInvalidated"))
        #expect(view.contains("test.consumeCorrelationAsyncInvalidation()"))
        #expect(!view.contains("milliseconds(100)"))
        #expect(!view.contains("correlationProgressTask"))
    }

    @Test("terminal consumer fails closed and preserves fresh-series restart semantics")
    func terminalConsumerDoesNotPromoteEvidence() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let consumer = try function(in: app, startingAt: "func consumeCorrelationAsyncInvalidation")

        #expect(consumer.contains("isSeriesInvalidated == true"))
        #expect(consumer.contains("phase == .baseline") || consumer.contains("phase == .scanning"))
        #expect(consumer.contains("abandonPackageCorrelation()"))
        #expect(consumer.contains("failLocally("))
        #expect(consumer.contains("target_correlation_async_invalidated"))
        #expect(consumer.contains("Restart from OFF1"))
        #expect(!consumer.contains("selectedID ="))
        #expect(!consumer.contains("pendingCorrelatedTargetID ="))
        #expect(!consumer.contains("targetCorrelationOperatorConfirmed = true"))
        #expect(!consumer.contains("beginOfficialConnection"))
    }

    private func function(in source: String, startingAt marker: String) throws -> Substring {
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
