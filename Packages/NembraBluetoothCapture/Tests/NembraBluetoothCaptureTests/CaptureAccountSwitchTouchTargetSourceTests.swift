import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Tuya account-switch touch target")
struct CaptureAccountSwitchTouchTargetSourceTests {
    @Test("quiet account-switch action retains a full 44-point rectangular hit target")
    func accountSwitchTargetIsAccessibleWithoutChangingHierarchy() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let preflight = String(try section(
            in: source,
            from: "private var preflightPanel: some View",
            to: "private var correlationDisplayedWindowOrdinal"
        ))
        let buttonStart = try #require(preflight.range(of: "Button(\"Use a different Tuya account\")"))
        let hint = try #require(preflight.range(
            of: ".accessibilityHint(\"Signs out of the official Tuya SDK account",
            range: buttonStart.lowerBound..<preflight.endIndex
        ))
        let button = String(preflight[buttonStart.lowerBound..<hint.upperBound])

        #expect(button.contains("sdkAccount.signOut()"))
        #expect(button.contains(".buttonStyle(.plain)"))
        #expect(button.contains(".frame(minHeight: 44, alignment: .leading)"))
        #expect(button.contains(".contentShape(Rectangle())"))
        #expect(button.contains(".disabled(test.membershipBusy || sdkAccount.busy)"))
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
