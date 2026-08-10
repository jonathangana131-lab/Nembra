import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Accessibility XXXL layout")
struct TuyaCaptureAccessibilityXXXLSourceTests {
    @Test("correlation header recomposes instead of squeezing title and window ordinal")
    func correlationHeaderRecomposesAtAccessibilitySizes() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let panel = String(try section(in: app, from: "private var correlationPanel: some View", to: "private var secureObservationPanel: some View"))

        #expect(panel.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(panel.contains("correlationDisplayedWindowOrdinal"))
        #expect(panel.contains("Correlation progress"))
        #expect(panel.contains("VStack(alignment: .leading"))
    }

    @Test("observation timer recomposes instead of squeezing label and seconds")
    func observationProgressRecomposesAtAccessibilitySizes() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let panel = String(try section(in: app, from: "private var secureObservationPanel: some View", to: "private var failureRecoveryContextPanel: some View"))

        #expect(panel.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(panel.contains("Authenticated observation"))
        #expect(panel.contains("Authenticated observation progress"))
        #expect(panel.contains("monospacedDigit"))
    }

    @Test("AX layout proof remains presentation-only and cannot create capture authority")
    func layoutHasNoAuthoritySideEffect() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let secureLinkView = String(try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable"))

        #expect(!secureLinkView.contains("NEMBRA_SIMULATION_"))
        #expect(!secureLinkView.contains("SIMCTL_CHILD_"))
        #expect(!secureLinkView.contains("publishDps"))
        #expect(!secureLinkView.contains("writeValue"))
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
