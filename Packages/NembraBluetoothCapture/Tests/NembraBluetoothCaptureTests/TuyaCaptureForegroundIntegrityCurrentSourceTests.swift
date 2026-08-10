import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current foreground integrity")
struct TuyaCaptureForegroundIntegrityCurrentSourceTests {
    @Test("foreground loss preserves sealed acceptance and revokes mutable account authority")
    func foregroundLossPreservesAcceptance() throws {
        let controller = try controllerSource()
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        #expect(cleanup.contains("guard phase != .accepted else { return }"))
        let verified = try offset("sdkDeviceMembershipVerified = false", cleanup)
        let status = try offset("membershipStatus =", cleanup)
        let request = try offset("membershipRequestID = UUID()", cleanup)
        #expect(verified < status)
        #expect(status < request)
        #expect(cleanup.contains("membershipAccountUID = nil"))
        #expect(cleanup.contains("membershipDeviceID = nil"))
    }

    @Test("already-correlated target cannot cross foreground or view lifetime")
    func correlatedTargetIsRetired() throws {
        let controller = try controllerSource()
        let exit = String(try section(in: controller, from: "func abandonCorrelationForViewExit()", to: "func appDidLoseForeground()"))
        let foreground = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        for cleanup in [exit, foreground] {
            #expect(cleanup.contains("phase == .correlated || phase == .selected"))
            #expect(cleanup.contains("resetDiscoverySessionOnly()"))
        }
        #expect(exit.contains("target_correlation_retired_on_view_exit"))
        #expect(foreground.contains("foreground_integrity_lost_after_target_correlation"))
    }

    @Test("accepted foreground terminals remain continuity truthful")
    func acceptedForegroundTerminalSemanticsRemain() throws {
        let controller = try controllerSource()
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(cleanup.contains("Relaunch Capture before a new stationary read-only attempt"))
        for forbidden in ["releasePackageCorrelationLease(", "recordObservedTransportLoss", "endConnection(", "disconnectBLE", "writeValue", "publishDps", "queryDps"] {
            #expect(!cleanup.contains(forbidden))
        }
    }

    @Test("view exit clears stale verified status and owns one terminal verdict")
    func viewExitRevokesStatus() throws {
        let controller = try controllerSource()
        let exit = String(try section(in: controller, from: "func abandonCorrelationForViewExit()", to: "func appDidLoseForeground()"))
        #expect(try offset("sdkDeviceMembershipVerified = false", exit) < offset("membershipStatus =", exit))
        #expect(try offset("membershipStatus =", exit) < offset("membershipRequestID = UUID()", exit))
        #expect(exit.contains("if foregroundIntegrityLossHandled { return }"))
        #expect(exit.contains("foregroundIntegrityLossHandled = true"))
        #expect(exit.contains("Task { @MainActor [self] in"))
    }

    private func controllerSource() throws -> String {
        let source = try entrypointSource()
        return String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
    }

    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private func offset(_ token: String, _ source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Missing source token: \(token)")
            throw SourceError.missing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Missing source section: \(start) ... \(end)")
            throw SourceError.missing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private enum SourceError: Error { case missing }
}