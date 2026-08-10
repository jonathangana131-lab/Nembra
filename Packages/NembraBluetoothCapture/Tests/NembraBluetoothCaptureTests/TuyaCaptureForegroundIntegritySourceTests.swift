import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground integrity source contract")
struct TuyaCaptureForegroundIntegritySourceTests {
    @Test("scene loss is idempotent and closes membership authority before transport")
    func sceneLossClosesAuthorityFirst() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        #expect(controller.contains("private var foregroundIntegrityLossHandled = false"))
        #expect(cleanup.contains("guard !foregroundIntegrityLossHandled else { return }"))
        let close = try offset("acceptsViewScopedMembershipRequests = false", cleanup)
        let verified = try offset("sdkDeviceMembershipVerified = false", cleanup)
        let request = try offset("membershipRequestID = UUID()", cleanup)
        let official = try offset("officialConnectionRequestID = UUID()", cleanup)
        let transport = try offset("if processCorrelationLease != nil || correlationSession != nil", cleanup)
        #expect(close < verified && verified < request && request < official && official < transport)
        #expect(cleanup.contains("membershipAccountUID = nil"))
        #expect(cleanup.contains("membershipDeviceID = nil"))
        #expect(cleanup.contains("watchdog?.cancel()"))
    }

    @Test("foreground loss distinguishes continuity from lifecycle and never claims disconnect")
    func usesTruthSpecificTerminal() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("let wasObserving = phase == .observing"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        for forbidden in ["releasePackageCorrelationLease()", "recordObservedTransportLoss", "endConnection", "disconnectBLE"] { #expect(!cleanup.contains(forbidden)) }
    }

    @Test("Secure Link current scene gates bootstrap and active return only re-verifies membership")
    func viewOwnsSceneBoundary() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = String(try section(in: source, from: "private struct SecureLinkView: View", to: "private var hero: some View"))
        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        let task = String(try section(in: view, from: ".task {", to: ".onDisappear {"))
        #expect(try offset("test.activateMembershipRequestsForView()",task) < offset("if scenePhase == .active",task))
        #expect(try offset("if scenePhase == .active",task) < offset("sdkAccount.bootstrap()",task))
        #expect(task.contains("test.appDidLoseForeground()"))
        let scene = String(try section(in: view, from: ".onChange(of: scenePhase)", to: ".onChange(of: sdkAccount.loggedIn)"))
        #expect(scene.contains("if newPhase == .active"))
        #expect(scene.contains("test.activateMembershipRequestsForView()"))
        #expect(scene.contains("test.verifySDKMembership()"))
        #expect(scene.contains("test.appDidLoseForeground()"))
        #expect(!scene.contains("startBaseline"))
        #expect(!scene.contains("beginOfficialConnection"))
    }

    @Test("view exit preserves strong terminal lifetime and marks scene loss handled")
    func viewExitAndSceneLossCannotDoubleTerminal() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let exit = String(try section(in: controller, from: "func abandonCorrelationForViewExit()", to: "func appDidLoseForeground()"))
        #expect(exit.contains("foregroundIntegrityLossHandled = true"))
        #expect(exit.contains("sdkDeviceMembershipVerified = false"))
        #expect(exit.contains("Task { @MainActor [self] in"))
    }

    private func offset(_ token:String,_ source:String)throws->String.Index { guard let r=source.range(of:token) else { Issue.record("Missing source token: \(token)"); throw E.missing }; return r.lowerBound }
    private func section(in source:String,from start:String,to end:String)throws->Substring { guard let a=source.range(of:start),let b=source.range(of:end,range:a.upperBound..<source.endIndex) else { Issue.record("Missing source section: \(start) ... \(end)"); throw E.missing }; return source[a.lowerBound..<b.lowerBound] }
    private func readRepositoryFile(_ relativePath:String)throws->String { let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(); return try String(contentsOf:root.appendingPathComponent(relativePath),encoding:.utf8) }
    private enum E: Error { case missing }
}
