import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground integrity source contract")
struct TuyaCaptureForegroundIntegritySourceTests {
    @Test("Secure Link owns an explicit active-scene evidence boundary")
    func secureLinkOwnsForegroundIntegrity() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = String(try section(in: source, from: "private struct SecureLinkView: View", to: "private var hero: some View"))

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains("if scenePhase == .active"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("if newPhase == .active"))
        #expect(view.contains("test.activateMembershipRequestsForView()"))
        #expect(view.contains("test.appDidLoseForeground()"))
    }

    @Test("foreground loss closes membership admission before revoking grants or transport")
    func foregroundLossOrdersAuthorityRevocation() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))

        let closeAdmission = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: cleanup)
        let revokeProof = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
        let revokeMembership = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
        let revokeOfficial = try requiredOffset(containing: "officialConnectionRequestID = UUID()", in: cleanup)
        let cancelWatchdog = try requiredOffset(containing: "watchdog?.cancel()", in: cleanup)
        let correlationCheck = try requiredOffset(containing: "if processCorrelationLease != nil || correlationSession != nil", in: cleanup)

        #expect(closeAdmission < revokeProof)
        #expect(revokeProof < revokeMembership)
        #expect(revokeMembership < revokeOfficial)
        #expect(revokeOfficial < cancelWatchdog)
        #expect(cancelWatchdog < correlationCheck)
        #expect(cleanup.contains("membershipProbe = nil"))
        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
    }

    @Test("foreground and navigation terminals cannot race the same ledger token")
    func exactTokenHasOneViewLifecycleTerminalOwner() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let navigation = String(try section(in: controller, from: "func abandonCorrelationForViewExit()", to: "func appDidLoseForeground()"))
        let foreground = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))

        #expect(controller.contains("private var terminalRetirementToken: TuyaReadOnlyConnectionToken?"))
        #expect(navigation.contains("guard terminalRetirementToken != token else"))
        #expect(navigation.contains("terminalRetirementToken = token"))
        #expect(navigation.contains("Task { @MainActor [self] in"))
        #expect(foreground.contains("guard terminalRetirementToken != token else"))
        #expect(foreground.contains("terminalRetirementToken = token"))
        #expect(foreground.contains("Task { @MainActor [self] in"))
        #expect(foreground.contains("self.terminalRetirementToken = nil"))
    }

    @Test("foreground terminal distinguishes observation continuity from authentication lifecycle")
    func foregroundTerminalUsesTruthfulPackageTerminal() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))

        #expect(cleanup.contains("let wasObserving = phase == .observing"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("Relaunch before a new stationary read-only attempt"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection"))
        #expect(!cleanup.contains("disconnectBLE"))
        #expect(!cleanup.contains("publishDps"))
        #expect(!cleanup.contains("queryDps"))
        #expect(!cleanup.contains("writeValue"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
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
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
