import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlation progress presentation")
struct TuyaCorrelationProgressPresentationSourceTests {
    @Test("package-owned async scan readiness is published into SwiftUI state")
    func progressIsPublished() throws {
        let app = try appSource()
        #expect(app.contains("@Published private(set) var correlationProgress: PassiveBluetoothPowerCycleObservationProgress?"))
        #expect(app.contains("private var correlationProgressTask: Task<Void, Never>?"))
        #expect(app.contains("startCorrelationProgressObservation(session: session)"))
        #expect(app.contains("self.correlationProgress = progress"))
        #expect(app.contains("Task.sleep(for: .milliseconds(100))"))
        #expect(app.contains("private func stopCorrelationProgressObservation()"))
        #expect(!app.contains("var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }"))
    }

    @Test("progress observer retires with discovery state")
    func observerRetires() throws {
        let app = try appSource()
        let reset = try section(app, from: "private func resetDiscoverySessionOnly()", to: "private func failLocally")
        #expect(reset.contains("stopCorrelationProgressObservation()"))
        #expect(reset.contains("correlationProgress = nil"))
        let failure = try section(app, from: "private func failLocally", to: "private func log")
        #expect(failure.contains("stopCorrelationProgressObservation()"))
        #expect(failure.contains("correlationProgress = nil"))
    }

    private func appSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private func section(_ source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            throw ContractError.missingSection
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private enum ContractError: Error { case missingSection }
}
