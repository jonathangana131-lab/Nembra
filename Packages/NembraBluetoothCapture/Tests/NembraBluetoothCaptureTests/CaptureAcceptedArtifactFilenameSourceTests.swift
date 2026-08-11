import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted artifact filename")
struct CaptureAcceptedArtifactFilenameSourceTests {
    @Test("accepted Capture and failed diagnostics use distinct truthful filenames")
    func acceptedAndFailedExportsNameTheirAuthorityClass() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let prepareExport = String(try section(
            in: source,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))
        let completion = String(try section(
            in: source,
            from: "private var completionPanel: some View",
            to: "private var sdkAuthorizationPanel: some View"
        ))
        let failed = String(try section(
            in: source,
            from: "private var failureDiagnosticsControls: some View",
            to: "private var completionPanel: some View"
        ))

        #expect(prepareExport.contains("if phase == .accepted"))
        #expect(prepareExport.contains("Nembra-Capture-\\(deviceID.prefix(8)).json"))
        #expect(prepareExport.contains("Nembra-Secure-Link-\\(deviceID.prefix(8))-Diagnostics.json"))
        #expect(completion.contains("Label(\"Share Capture\""))
        #expect(completion.contains("name: test.exportName"))
        #expect(failed.contains("Label(\"Share diagnostics\""))
        #expect(failed.contains("name: test.exportName"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
