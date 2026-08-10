import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture navigation BLE lease retirement source contract")
struct TuyaNavigationBLELeaseRetirementSourceTests {
    @Test("leaving Secure Link deterministically retires package correlation before controller loss")
    func secureLinkNavigationExitRetiresCorrelationLease() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let view = String(try section(
            in: source,
            from: "private struct SecureLinkView: View",
            to: "private extension SecureLinkView"
        ))

        #expect(controller.contains("func abandonCorrelationForViewExit()"))
        #expect(controller.contains("abandonPackageCorrelation()"))
        #expect(view.contains(".onDisappear"))
        #expect(view.contains("test.abandonCorrelationForViewExit()"))
    }

    @Test("current package correlation transport has explicit abandonment API used by app cleanup")
    func packageTransportRetirementRemainsExplicit() throws {
        let source = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothPowerCycleObservationSession.swift"
        )
        #expect(source.contains("public func abandonCurrentWindow()"))
        #expect(source.contains("manager.stopScan()"))
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
