import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture account-switch accessibility")
struct TuyaAccountSwitchAccessibilitySourceTests {
    @Test("quiet account-switch action keeps a full stopped-state hit target")
    func accountSwitchHasMinimumTouchTarget() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let preflight = String(try section(
            in: source,
            from: "private var preflightPanel: some View",
            to: "private var correlationDisplayedWindowOrdinal"
        ))
        let accountSwitch = String(try section(
            in: preflight,
            from: "Button(\"Use a different Tuya account\")",
            to: "if authorityReady"
        ))

        #expect(accountSwitch.contains(".buttonStyle(.plain)"))
        #expect(accountSwitch.contains("minHeight: 44"))
        #expect(accountSwitch.contains(".contentShape(Rectangle())"))
        #expect(accountSwitch.contains(".disabled(test.membershipBusy || sdkAccount.busy)"))
        #expect(accountSwitch.contains(".accessibilityHint("))
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
