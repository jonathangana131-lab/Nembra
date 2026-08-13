import Foundation
import Testing

extension TuyaAppIncompleteHorizonTerminalSourceTests {
    @Test("application callback classifies the package incomplete horizon explicitly")
    func applicationUpdateHasDedicatedIncompleteHorizonCatch() throws {
        let source = try String(
            contentsOf: repositoryRootForApplicationTerminalTest()
                .appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
        guard let start = source.range(of: "private func receivedApplicationUpdate"),
              let end = source.range(of: "private func startWatchdog", range: start.upperBound..<source.endIndex) else {
            Issue.record("Expected application-update source section missing")
            return
        }
        let applicationUpdate = String(source[start.lowerBound..<end.lowerBound])
        #expect(applicationUpdate.contains(
            "catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached"
        ))
    }
}

private func repositoryRootForApplicationTerminalTest() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
