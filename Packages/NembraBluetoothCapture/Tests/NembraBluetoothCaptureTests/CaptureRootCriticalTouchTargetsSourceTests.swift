import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture root critical touch targets")
struct CaptureRootCriticalTouchTargetsSourceTests {
    @Test("critical account recovery and scooter-selection controls guarantee a large touch target")
    func rootSetupControlsMeetOutdoorTouchTargetContract() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: source,
            from: "private struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class TuyaAccountBridge"
        ))

        for token in [
            "Button(\"Reset account link\")",
            "Button(\"Refresh\")",
            "Button(tuya.selectedDeviceID == device.id ? \"Refresh metadata\" : \"Use this scooter\")",
            "NavigationLink(\"Continue to Capture\")",
        ] {
            let control = try controlWindow(containing: token, in: root)
            #expect(
                control.contains(".controlSize(.large)") || control.contains(".frame(minHeight: 44"),
                "Critical root control lacks a large/44-point target: \(token)"
            )
        }
    }

    private func controlWindow(containing token: String, in source: String) throws -> String {
        guard let range = source.range(of: token) else {
            Issue.record("Expected control token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        let end = source.index(range.lowerBound, offsetBy: 260, limitedBy: source.endIndex) ?? source.endIndex
        return String(source[range.lowerBound..<end])
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
