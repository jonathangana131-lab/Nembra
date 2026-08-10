import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground integrity and stationary recovery")
struct TuyaForegroundStationaryRecoverySourceTests {
    @Test("Secure Link fails closed once when foreground authority is lost")
    func foregroundLossRevokesAuthorityAndRetiresExactGeneration() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        let view = String(try section(in: source, from: "private struct SecureLinkView: View", to: "private var hero: some View"))

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("test.appDidLoseForeground()"))

        let admissionClose = try offset("acceptsViewScopedMembershipRequests = false", in: cleanup)
        let proofRevoke = try offset("sdkDeviceMembershipVerified = false", in: cleanup)
        let membershipRevoke = try offset("membershipRequestID = UUID()", in: cleanup)
        let officialRevoke = try offset("officialConnectionRequestID = UUID()", in: cleanup)
        let stateInspection = try offset("if processCorrelationLease != nil || correlationSession != nil", in: cleanup)
        #expect(admissionClose < proofRevoke)
        #expect(proofRevoke < membershipRevoke)
        #expect(membershipRevoke < stateInspection)
        #expect(officialRevoke < stateInspection)
        #expect(cleanup.contains("membershipAccountUID = nil"))
        #expect(cleanup.contains("membershipDeviceID = nil"))
        #expect(cleanup.contains("guard hadViewAuthority else { return }"))
        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(!cleanup.contains("Task { @MainActor [weak self]"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection("))
        #expect(!cleanup.contains("disconnectBLE("))
    }

    @Test("post-handoff recovery never asks for a same-process OFF1 restart or an outdoor ride")
    func postHandoffRecoveryRequiresStationaryRelaunch() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let postHandoff = String(try section(in: source, from: "private func beginOfficialConnection(candidate: Candidate)", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))

        #expect(!postHandoff.lowercased().contains("restart from off1"))
        #expect(!postHandoff.lowercased().contains("ride capture"))
        #expect(!postHandoff.lowercased().contains("outdoor ride"))
        #expect(postHandoff.components(separatedBy: "Export diagnostics; relaunch Capture before any new stationary read-only attempt.").count - 1 == 2)

        let required = [
            "Source authority changed while canonical acceptance was sealing. Relaunch Capture before a new stationary read-only attempt; the sealed package chronology is diagnostic only.",
            "Tuya local-BLE authority became unavailable after canonical acceptance sealed. Relaunch Capture before a new stationary read-only attempt; no disconnect time is inferred.",
            "Tuya local-BLE authority was no longer current after canonical acceptance sealed. Relaunch Capture before a new stationary read-only attempt; no disconnect time is inferred.",
            "Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable. Relaunch Capture before a new stationary read-only attempt; do not rebuild accepted evidence from mutable post-seal state."
        ]
        for message in required { #expect(postHandoff.contains(message)) }
    }

    private func offset(_ token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return range.lowerBound
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
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
