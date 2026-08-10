import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed recovery presentation truth")
struct TuyaSecureLinkFailedRecoveryPresentationTruthSourceTests {
    @Test("failed hero copy follows controller restart authority")
    func failedHeroDoesNotPromiseUnsafeInProcessRestart() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let subtitle = try section(
            in: app,
            from: "private var phaseSubtitle: String",
            to: "private var heroSymbol: String"
        )
        let body = String(subtitle)

        #expect(body.contains("case .failed:"))
        #expect(body.contains("test.canRestartFromFreshOFF1"), Comment(rawValue: "The hero must consume the same lifecycle authority that gates the failure panel."))
        #expect(body.contains("Relaunch Capture"), Comment(rawValue: "An unretired generation must not be told to restart from OFF1 in-process."))
        #expect(body.contains("restart from scooter OFF"), Comment(rawValue: "A safely retired generation may retain the fresh OFF1 recovery path."))
    }

    @Test("failed kicker cannot call an unretired generation stopped safely")
    func failedKickerUsesLifecycleTruth() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let kicker = try section(
            in: app,
            from: "private var phaseKicker: String",
            to: "private var phaseTitle: String"
        )
        let body = String(kicker)

        #expect(body.contains("case .failed:"))
        #expect(body.contains("test.canRestartFromFreshOFF1"), Comment(rawValue: "Generic `.failed` is not enough authority for `STOPPED SAFELY` when package ownership may remain unresolved."))
        #expect(body.contains("STOPPED SAFELY"))
        #expect(body.contains("RELAUNCH REQUIRED") || body.contains("CAPTURE PAUSED"), Comment(rawValue: "The relaunch-only case needs neutral/explicit wording rather than a safe-retirement claim."))
    }

    @Test("failure panel and hero share one recovery boundary")
    func failureSurfacesDoNotContradictEachOther() throws {
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
