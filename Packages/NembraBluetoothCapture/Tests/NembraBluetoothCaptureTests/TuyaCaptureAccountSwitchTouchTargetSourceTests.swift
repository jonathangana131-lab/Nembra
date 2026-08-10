import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture account-switch touch target")
struct TuyaCaptureAccountSwitchTouchTargetSourceTests {
    @Test("secondary account switch remains understated but exposes a 44 point stopped-state hit target")
    func accountSwitchHasMinimumTouchTarget() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let preflight = String(try section(
            in: source,
            from: "private var preflightPanel: some View",
            to: "private var correlationDisplayedWindowOrdinal"
        ))
        let button = String(try section(
            in: preflight,
            from: "Button(\"Use a different Tuya account\")",
            to: ".accessibilityHint(\"Signs out of the official Tuya SDK account"
        ))

        #expect(button.contains(".buttonStyle(.plain)"))
        #expect(
            button.contains(".frame(minHeight: 44")
                || button.contains(".frame(minHeight: 44.0")
        )
        #expect(button.contains(".contentShape(Rectangle())"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw ContractError.missing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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

    private enum ContractError: Swift.Error { case missing }
}
