import Foundation
import Testing

@Suite("ES80 Capture restart failure-copy acceptance")
struct ES80CaptureRestartFailureCopyAcceptanceTests {
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

    @Test("fresh-run construction failure never dumps implementation error text into rider UI")
    func restartFailureStaysRiderSafe() throws {
        let source = try Self.shellSource()
        let beginning = try #require(source.range(of: "private func restartExperiment()"))
        let end = try #require(
            source.range(
                of: "private func handleScenePhaseChange",
                range: beginning.lowerBound..<source.endIndex
            )
        )
        let restartSurface = source[beginning.lowerBound..<end.lowerBound]

        #expect(
            !restartSurface.contains("String(describing: error)"),
            "A fresh-run construction failure is rider-facing; raw Swift error descriptions must stay out of the primary Capture surface."
        )
        #expect(!restartSurface.contains("package-owned"))
        #expect(!restartSurface.contains("CoreBluetooth"))
        #expect(restartSurface.contains("Nembra could not start a fresh capture."))
        #expect(restartSurface.contains("Try again."))
    }
}
