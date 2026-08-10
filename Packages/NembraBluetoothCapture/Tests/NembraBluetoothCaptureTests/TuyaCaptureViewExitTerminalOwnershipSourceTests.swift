import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture view-exit terminal ownership")
struct TuyaCaptureViewExitTerminalOwnershipSourceTests {
    @Test("normal view exit claims the view-lifetime terminal before retiring active authority")
    func viewExitClaimsTerminalBeforeAuthorityRetirement() throws {
        let source = try entrypointSource()
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "func appDidLoseForeground()"
        ))
        let ownership = String(try section(
            in: cleanup,
            from: "if foregroundIntegrityLossHandled { return }",
            to: "if let token = currentConnectionToken"
        ))

        #expect(ownership.contains("foregroundIntegrityLossHandled = true"))
        #expect(ownership.components(separatedBy: "foregroundIntegrityLossHandled = true").count == 2)
    }

    @Test("scene foreground loss cannot claim a second terminal after view exit")
    func sceneLossUsesSameTerminalFence() throws {
        let source = try entrypointSource()
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let foreground = String(try section(
            in: controller,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))

        let guardRange = try #require(foreground.range(of: "guard !foregroundIntegrityLossHandled else { return }"))
        let claimRange = try #require(foreground.range(of: "foregroundIntegrityLossHandled = true"))
        #expect(guardRange.lowerBound < claimRange.lowerBound)
    }

    @Test("view exit keeps strong exact-generation retirement")
    func activeGenerationRetirementRemainsStrongAndExact() throws {
        let source = try entrypointSource()
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "func appDidLoseForeground()"
        ))
        let active = String(try section(
            in: cleanup,
            from: "if let token = currentConnectionToken",
            to: "if phase == .authenticating"
        ))

        #expect(active.contains("Task { @MainActor [self] in"))
        #expect(active.contains("invalidateInternalLifecycle("))
        #expect(active.contains("token: token"))
        #expect(!active.contains("[weak self]"))
        #expect(!active.contains("disconnectBLE"))
    }

    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceError.missing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private enum SourceError: Error { case missing }
}