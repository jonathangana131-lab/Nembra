import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field build identity")
struct CaptureFieldBuildIdentityTests {
    private let sha = "0123456789abcdef0123456789abcdef01234567"

    @Test("accepts human label plus exact full Git SHA")
    func acceptsStampedIdentity() {
        let identity = CaptureFieldBuildIdentity(
            buildIdentifier: "Authenticated stationary capture 0123456789ab",
            commitSHA: sha.uppercased()
        )

        #expect(identity?.buildIdentifier == "Authenticated stationary capture 0123456789ab")
        #expect(identity?.commitSHA == sha)
        #expect(identity?.shortCommitSHA == "0123456789ab")
    }

    @Test("rejects missing unresolved or placeholder provenance")
    func rejectsUnstampedIdentity() {
        #expect(CaptureFieldBuildIdentity(buildIdentifier: nil, commitSHA: sha) == nil)
        #expect(CaptureFieldBuildIdentity(buildIdentifier: "", commitSHA: sha) == nil)
        #expect(CaptureFieldBuildIdentity(buildIdentifier: "Nembra Capture unstamped", commitSHA: sha) == nil)
        #expect(CaptureFieldBuildIdentity(buildIdentifier: "$(NEMBRA_CAPTURE_BUILD_IDENTIFIER)", commitSHA: sha) == nil)
        #expect(CaptureFieldBuildIdentity(buildIdentifier: "Field build", commitSHA: nil) == nil)
    }

    @Test("requires full forty-character hexadecimal Git SHA")
    func requiresFullGitSHA() {
        #expect(CaptureFieldBuildIdentity(buildIdentifier: "Field build", commitSHA: "0123456789ab") == nil)
        #expect(CaptureFieldBuildIdentity(buildIdentifier: "Field build", commitSHA: String(repeating: "g", count: 40)) == nil)
        #expect(CaptureFieldBuildIdentity(buildIdentifier: "Field build", commitSHA: String(repeating: "a", count: 39)) == nil)
        #expect(CaptureFieldBuildIdentity(buildIdentifier: "Field build", commitSHA: String(repeating: "a", count: 41)) == nil)
    }

    @Test("reads only canonical Info.plist provenance keys")
    func infoDictionaryContract() {
        let identity = CaptureFieldBuildIdentity.from(infoDictionary: [
            CaptureFieldBuildIdentity.buildIdentifierInfoKey: "Authenticated stationary capture 0123456789ab",
            CaptureFieldBuildIdentity.commitSHAInfoKey: sha,
            "OtherSHA": String(repeating: "f", count: 40)
        ])

        #expect(identity?.commitSHA == sha)
        #expect(identity?.buildIdentifier == "Authenticated stationary capture 0123456789ab")
    }
}
