import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field installer signed-bundle verification")
struct TuyaFieldInstallerSignedBundleVerificationSourceTests {
    @Test("strict recursive signature validation precedes entitlement authority and install")
    func signedBundleSealMustValidateBeforeAuthorityReadbackOrDeviceInstall() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        let verify = try requiredOffset(
            containing: "/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign --verify --deep --strict \"$APP\"",
            in: installer
        )
        let entitlementReadback = try requiredOffset(
            containing: "/usr/bin/codesign -d --entitlements :- --xml \"$APP\"",
            in: installer
        )
        let install = try requiredOffset(
            containing: "xcrun devicectl device install app --device \"$COREDEVICE_ID\" \"$APP\"",
            in: installer
        )

        #expect(verify < entitlementReadback)
        #expect(entitlementReadback < install)
        #expect(installer.contains("failed recursive strict code-signature verification"))
        #expect(installer.contains("passed recursive strict code-signature verification"))
    }

    @Test("verification is validation-only and closed-environment")
    func verifierCannotResignOrInheritCallerToolingEnvironment() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let verifyLine = try requiredLine(
            containing: "/usr/bin/codesign --verify --deep --strict \"$APP\"",
            in: installer
        )

        #expect(verifyLine.contains("/usr/bin/env -i PATH=/usr/bin:/bin"))
        #expect(verifyLine.contains("--verify"))
        #expect(verifyLine.contains("--deep"))
        #expect(verifyLine.contains("--strict"))
        #expect(!verifyLine.contains("--sign"))
        #expect(!verifyLine.contains("--force"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.tokenMissing
        }
        return range.lowerBound
    }

    private func requiredLine(containing token: String, in source: String) throws -> String {
        guard let line = source.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first(where: { $0.contains(token) }) else {
            Issue.record("Expected source line missing: \(token)")
            throw SourceContractError.tokenMissing
        }
        return line
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

    private enum SourceContractError: Error { case tokenMissing }
}
