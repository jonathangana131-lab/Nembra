import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Field authorization production trust root")
struct PassiveBluetoothCaptureFieldAuthorizationTrustRootTests {
    @Test("production trust root remains deliberately unconfigured while physical capture is NO-GO")
    func productionTrustRootIsFailClosedUntilIndependentlyPinned() {
        #expect(PassiveBluetoothCaptureFieldAuthorizationTrustAnchor.publicKeyX963Representation == nil)
    }

    @Test("production verifier cannot select its authorization key from running-bundle metadata")
    func runningBundleCannotSelfSelectAuthorizationAuthority() throws {
        let source = try Self.source()

        #expect(source.contains("PassiveBluetoothCaptureFieldAuthorizationTrustAnchor"))
        #expect(source.contains("authorizationTrustAnchorNotConfigured"))
        #expect(!source.contains("NembraCaptureFieldAuthorizationPublicKeyX963Base64"))
        #expect(!source.contains("Bundle.main.infoDictionary?["))
        #expect(source.contains("package static func verify("))
    }

    private static func source() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/NembraBluetoothCapture/PassiveBluetoothCaptureFieldAuthorization.swift"
            ),
            encoding: .utf8
        )
    }
}
