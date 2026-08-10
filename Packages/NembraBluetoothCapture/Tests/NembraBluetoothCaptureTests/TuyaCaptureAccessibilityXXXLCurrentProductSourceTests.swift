import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current-product Accessibility XXXL layout")
struct TuyaCaptureAccessibilityXXXLCurrentProductSourceTests {
    @Test("correlation header recomposes instead of squeezing title and window ordinal")
    func correlationHeaderRecomposesAtAccessibilitySizes() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let panel = String(try section(in: app, from: "private var correlationPanel: some View", to: "private var secureObservationPanel: some View"))
        #expect(panel.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(panel.contains("correlationDisplayedWindowOrdinal"))
        #expect(panel.contains("accessibilityLabel(\"Correlation progress\")"))
        #expect(panel.contains("accessibilityValue(\"\\(correlationDisplayedWindowOrdinal) of 4 windows\")"))
        #expect(panel.contains("VStack(alignment: .leading"))
    }

    @Test("read-only observation timer recomposes instead of squeezing label and seconds")
    func observationProgressRecomposesAtAccessibilitySizes() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let panel = String(try section(in: app, from: "private var secureObservationPanel: some View", to: "private var failureRecoveryContextPanel: some View"))
        #expect(panel.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(panel.contains("Read-only observation"))
        #expect(panel.contains("accessibilityLabel(\"Read-only observation progress\")"))
        #expect(panel.contains("accessibilityValue(\"\\(Int(min(age, 45))) of 45 seconds\")"))
        #expect(panel.contains("monospacedDigit"))
    }

    @Test("AX layout remains presentation-only and preserves current restart and BLE authorities")
    func layoutHasNoAuthoritySideEffect() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let secureLinkView = String(try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable"))
        #expect(!secureLinkView.contains("NEMBRA_SIMULATION_"))
        #expect(!secureLinkView.contains("SIMCTL_CHILD_"))
        #expect(!secureLinkView.contains("publishDps"))
        #expect(!secureLinkView.contains("writeValue"))
        #expect(secureLinkView.contains("SignInWithAppleButton(.signIn)"))

        let failure = String(try section(in: secureLinkView, from: "private var failurePanel: some View", to: "private var completionPanel: some View"))
        #expect(failure.contains("if test.canRestartFromFreshOFF1"))
        #expect(failure.contains("test.retry()"))
        #expect(failure.contains(".disabled(!authorityReady || test.membershipBusy)"))
        #expect(failure.contains("Relaunch Capture before another attempt"))

        let controller = String(try section(in: app, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        #expect(controller.contains("private var processCorrelationLease: UUID?"))
        #expect(controller.contains("OfficialTuyaFactory.acquirePackageCorrelationLease()"))
        #expect(controller.contains("OfficialTuyaFactory.releasePackageCorrelationLease(processCorrelationLease)"))
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
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
