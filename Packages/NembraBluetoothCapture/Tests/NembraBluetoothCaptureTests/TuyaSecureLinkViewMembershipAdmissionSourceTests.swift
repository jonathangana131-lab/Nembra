import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link view-lifetime membership admission")
struct TuyaSecureLinkViewMembershipAdmissionSourceTests {
    @Test("view exit closes admission before revoking current async grants")
    func exitClosesAdmissionBeforeGenerationRevocation() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func abandonCorrelationForViewExit()", to: "var privateConfig: Bool"))

        let close = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: cleanup)
        let membershipRevoke = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
        let officialRevoke = try requiredOffset(containing: "officialConnectionRequestID = UUID()", in: cleanup)
        let activeTokenBranch = try requiredOffset(containing: "if let token = currentConnectionToken", in: cleanup)
        #expect(close < membershipRevoke)
        #expect(membershipRevoke < officialRevoke)
        #expect(officialRevoke < activeTokenBranch)
    }

    @Test("membership verification cannot mint a new probe after view exit")
    func verificationRequiresOpenViewAdmissionBeforeAnyMembershipMutation() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let verification = String(try section(in: controller, from: "func verifySDKMembership(completion:", to: "func retry()"))

        let admission = try requiredOffset(containing: "guard acceptsViewScopedMembershipRequests else", in: verification)
        let clearLease = try requiredOffset(containing: "membershipAccountUID = nil", in: verification)
        let newRequest = try requiredOffset(containing: "let requestID = UUID()", in: verification)
        #expect(admission < clearLease)
        #expect(admission < newRequest)
        #expect(verification.contains("completion?(false)"))
    }

    @Test("appearance reopens admission before account bootstrap")
    func appearanceOpensAdmissionBeforeAccountBootstrap() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = String(try section(in: source, from: "private struct SecureLinkView: View", to: "private var hero: some View"))
        let task = String(try section(in: view, from: ".task {", to: ".onDisappear {"))
        let disappear = String(try section(in: view, from: ".onDisappear {", to: ".onChange(of: sdkAccount.loggedIn)"))
        let accountChangeStart = try requiredOffset(containing: ".onChange(of: sdkAccount.loggedIn)", in: view)
        let accountChange = String(view[accountChangeStart...])

        let open = try requiredOffset(containing: "test.activateMembershipRequestsForView()", in: task)
        let bootstrap = try requiredOffset(containing: "sdkAccount.bootstrap()", in: task)
        #expect(open < bootstrap)
        #expect(disappear.contains("test.abandonCorrelationForViewExit()"))
        #expect(accountChange.contains("if loggedIn { test.verifySDKMembership() }"))
        #expect(accountChange.contains("else { test.invalidateSDKMembership() }"))
    }

    @Test("screen-lifetime fence adds no transport or physical authority")
    func lifecycleFenceIsAuthorityNeutral() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let activation = String(try section(in: controller, from: "func activateMembershipRequestsForView()", to: "func abandonCorrelationForViewExit()"))
        #expect(activation.contains("acceptsViewScopedMembershipRequests = true"))
        for forbidden in ["connectBLE", "disconnectBLE", "publishDps", "queryDps", "writeValue", "SIMCTL_CHILD_", "NEMBRA_SIMULATION_"] {
            #expect(!activation.contains(forbidden))
        }
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
