import Foundation
import Testing

@Suite("ES80 Capture failure-guidance rider-language acceptance")
struct ES80CaptureFailureGuidanceRiderLanguageAcceptanceTests {
    private static func shellSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("Features")
                .appendingPathComponent("Research")
                .appendingPathComponent("ES80CaptureShellView.swift"),
            encoding: .utf8
        )
    }

    private static func slice(_ source: String, from start: String, to end: String) throws -> Substring {
        let lower = try #require(source.range(of: start))
        let upper = try #require(source.range(of: end, range: lower.lowerBound..<source.endIndex))
        return source[lower.lowerBound..<upper.lowerBound]
    }

    @Test("operational failures tell the rider what to do, not how the implementation is structured")
    func operationalFailuresAreHumanFirst() throws {
        let source = try Self.shellSource()
        let failureCopy = try Self.slice(source, from: "private func experimentErrorMessage", to: "private func bluetoothUnavailableMessage")
        let forbidden = ["correlated target", "rediscovery", "evidence gap", "non-connectable", "observation-window", "correlation window", "minimum observation period"]
        for phrase in forbidden { #expect(!failureCopy.localizedCaseInsensitiveContains(phrase)) }
        #expect(failureCopy.contains("Start again from OFF 1."))
        #expect(failureCopy.contains("Start a fresh capture."))
        #expect(failureCopy.contains("Keep the scooter ON and keep scanning."))
        #expect(failureCopy.contains("required observation time"))
    }

    @Test("Bluetooth blockers remain actionable without developer vocabulary")
    func bluetoothBlockersAreHumanFirst() throws {
        let source = try Self.shellSource()
        let bluetoothCopy = try Self.slice(source, from: "private func bluetoothUnavailableMessage", to: "private func statePanel")
        #expect(!bluetoothCopy.contains("radio becomes ready"))
        #expect(!bluetoothCopy.contains("passive capture"))
        #expect(!bluetoothCopy.contains("starting correlation"))
        #expect(bluetoothCopy.contains("before starting OFF 1"))
        #expect(bluetoothCopy.contains("Keep Nembra open until Bluetooth becomes ready"))
    }
}
