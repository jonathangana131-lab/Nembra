import Foundation
import Testing

@Suite("Capture root field-build authority")
struct TuyaCaptureRootFieldBuildAuthoritySourceTests {
    @Test("public root visibly fails closed when physical Capture is unavailable")
    func publicRootProjectsFieldBuildAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(
            try section(
                in: app,
                from: "private struct CaptureP0Root: View",
                to: "private final class SecureLinkController"
            )
        )

        #expect(root.contains("NembraCaptureBuildIdentity.current"))
        #expect(root.contains("isAuthoritativeFieldBuild"))
        #expect(root.contains("Field build ready"))
        #expect(root.contains("Physical capture locked"))
        #expect(root.contains("account metadata"))
        #expect(root.contains("cannot scan"))
        #expect(root.contains("physical scooter evidence"))

        #expect(!root.contains("writeValue"))
        #expect(!root.contains("publishDps"))
        #expect(!root.contains("SIMCTL_CHILD_"))
        #expect(!root.contains("NEMBRA_SIMULATION_"))
    }

    @Test("physical continuation is gated by authoritative field build")
    func continueActionRequiresAuthoritativeFieldBuild() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(
            try section(
                in: app,
                from: "private struct CaptureP0Root: View",
                to: "private final class SecureLinkController"
            )
        )
        let continuation = String(
            try section(
                in: root,
                from: "private func continueButton",
                to: "private var engineeringDisclosure"
            )
        )

        #expect(continuation.contains("isAuthoritativeFieldBuild"))
        #expect(continuation.contains("NavigationLink(\"Continue to Capture\")"))
        #expect(continuation.contains("View locked preflight"))
    }
}
