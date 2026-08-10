import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground integrity source contract")
struct TuyaCaptureForegroundIntegritySourceTests {
    @Test("foreground loss closes view admission before revoking async starts and transport")
    func foregroundLossClosesAdmissionFirst() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        let closeAdmission = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: cleanup)
        let membershipRevoke = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
        let officialRevoke = try requiredOffset(containing: "officialConnectionRequestID = UUID()", in: cleanup)
        let correlationCheck = try requiredOffset(containing: "if processCorrelationLease != nil || correlationSession != nil", in: cleanup)
        #expect(closeAdmission < membershipRevoke)
        #expect(membershipRevoke < officialRevoke)
        #expect(officialRevoke < correlationCheck)
        #expect(cleanup.contains("membershipBusy = false"))
        #expect(cleanup.contains("membershipProbe = nil"))
        #expect(cleanup.contains("watchdog?.cancel()"))
        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection"))
        #expect(!cleanup.contains("disconnectBLE"))
    }
    @Test("Secure Link observes scene activity and never silently reopens authority")
    func secureLinkOwnsForegroundBoundary() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = String(try section(in: source, from: "private struct SecureLinkView: View", to: "private var hero: some View"))
        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("if newPhase != .active"))
        #expect(view.contains("test.appDidLoseForeground()"))
        #expect(!view.contains("if newPhase == .active { test.activateMembershipRequestsForView()"))
    }
    private func requiredOffset(containing token: String, in source: String) throws -> String.Index { guard let r=source.range(of: token) else { throw SourceContractError.sectionMissing }; return r.lowerBound }
    private func section(in source: String, from start: String, to end: String) throws -> Substring { guard let a=source.range(of:start), let b=source.range(of:end,range:a.upperBound..<source.endIndex) else { throw SourceContractError.sectionMissing }; return source[a.lowerBound..<b.lowerBound] }
    private func readRepositoryFile(_ relativePath: String) throws -> String { let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(); return try String(contentsOf: root.appendingPathComponent(relativePath), encoding:.utf8) }
    private enum SourceContractError: Error { case sectionMissing }
}
