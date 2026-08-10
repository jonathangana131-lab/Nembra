import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed hero recovery truth")
struct TuyaSecureLinkFailedHeroRecoveryTruthSourceTests {
    @Test("failed hero recovery copy follows controller restart authority")
    func failedHeroDoesNotPromiseAnUnsafeInProcessRestart() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let subtitle = try section(
            in: app,
            from: "private var phaseSubtitle: String",
            to: "private var heroSymbol: String"
        )
        let body = String(subtitle)

        #expect(body.contains("case .failed:"))
        #expect(body.contains("test.canRestartFromFreshOFF1"), Comment(rawValue: "The failed hero must consume the same lifecycle authority that gates the failure panel; generic field readiness cannot authorize an in-process OFF1 retry."))
        #expect(body.contains("Relaunch Capture"), Comment(rawValue: "A retained/unretired generation must have truthful relaunch-only hero copy instead of an unconditional OFF1 restart instruction."))
        #expect(body.contains("restart from scooter OFF"), Comment(rawValue: "A safely retired generation may still present the normal fresh-OFF1 recovery path."))
    }

    @Test("failure panel and hero cannot disagree about relaunch-only recovery")
    func failureSurfacesShareOneRecoveryBoundary() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let failurePanel = try section(
            in: app,
            from: "private var failurePanel: some View",
            to: "private var completionPanel: some View"
        )
        let subtitle = try section(
            in: app,
            from: "private var phaseSubtitle: String",
            to: "private var heroSymbol: String"
        )

        #expect(failurePanel.contains("test.canRestartFromFreshOFF1"))
        #expect(failurePanel.contains("Relaunch Capture before another attempt"))
        #expect(subtitle.contains("test.canRestartFromFreshOFF1"))
        #expect(subtitle.contains("Relaunch Capture"))
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
