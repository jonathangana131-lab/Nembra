import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlation-progress presentation bridge")
struct TuyaCorrelationProgressPresentationSourceTests {
    @Test("package scan-readiness progress is published instead of pulled from an unobservable session")
    func correlationProgressHasAppOwnedPublishedSnapshot() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("@Published private(set) var correlationProgress"))
        #expect(!app.contains("var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }"))
        #expect(app.contains("private var correlationProgressTask: Task<Void, Never>?"))

        let liveProjection = try section(
            in: app,
            from: "var correlationWindowIsScanning",
            to: "var correlationWindowLabel"
        )
        #expect(liveProjection.contains("correlationProgress?.isScanning == true"))
        #expect(!liveProjection.contains("correlationSession?.progress"))
    }

    @Test("starting a window bridges asynchronous package readiness into the controller")
    func startWindowStartsPresentationObservation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let start = try section(
            in: app,
            from: "private func startCurrentCorrelationWindow()",
            to: "func finishCorrelationWindow()"
        )

        #expect(start.contains("session.startCurrentWindow()"))
        #expect(start.contains("startCorrelationProgressObservation(session:"))

        let observer = try section(
            in: app,
            from: "private func startCorrelationProgressObservation",
            to: "private func stopCorrelationProgressObservation"
        )
        #expect(observer.contains("session.progress"))
        #expect(observer.contains("self.correlationProgress = progress"))
        #expect(observer.contains("Task.sleep"))
        #expect(observer.contains("Task.isCancelled"))
    }

    @Test("presentation observer is retired at window or attempt boundaries")
    func progressObserverCannotLeakAcrossWindowsOrAttempts() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        let finish = try section(
            in: app,
            from: "func finishCorrelationWindow()",
            to: "private func finishCorrelationSeries"
        )
        #expect(finish.contains("stopCorrelationProgressObservation"))

        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly",
            to: "private func failLocally"
        )
        #expect(reset.contains("stopCorrelationProgressObservation"))
        #expect(reset.contains("correlationProgress = nil"))

        let stop = try section(
            in: app,
            from: "private func stopCorrelationProgressObservation",
            to: "private func"
        )
        #expect(stop.contains("correlationProgressTask?.cancel()"))
        #expect(stop.contains("correlationProgressTask = nil"))
    }

    @Test("primary seal affordance remains gated by published package scan liveness")
    func sealActionUsesPublishedLiveness() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = try section(in: app, from: "private struct SecureLinkView", to: "#Preview")

        #expect(view.contains("test.correlationWindowIsScanning"))
        #expect(view.contains(".disabled(!test.correlationWindowIsScanning)"))
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
