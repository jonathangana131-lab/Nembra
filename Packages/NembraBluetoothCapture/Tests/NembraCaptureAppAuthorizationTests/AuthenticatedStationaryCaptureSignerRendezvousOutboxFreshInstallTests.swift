import Foundation
import Testing
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary Capture signer rendezvous fresh-install bootstrap")
struct AuthenticatedStationaryCaptureSignerRendezvousOutboxFreshInstallTests {
    @Test("transport bootstrap creates a missing Application Support base before child directories")
    func createsMissingApplicationSupportBase() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: parent) }

        let applicationSupport = parent.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(atPath: applicationSupport.path))

        let outbox = AuthenticatedStationaryCaptureSignerRendezvousOutbox(
            applicationSupportURL: applicationSupport
        )
        try outbox.prepareAuthorizationTransferDirectory()
        try outbox.prepareAuthorizationTransferDirectory()

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(
            atPath: applicationSupport.path,
            isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)

        let transferDirectory = applicationSupport.appendingPathComponent(
            AuthenticatedStationaryCaptureAuthorizationInbox.directoryName,
            isDirectory: true
        )
        #expect(FileManager.default.fileExists(
            atPath: transferDirectory.path,
            isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)
        #expect(try FileManager.default.contentsOfDirectory(atPath: transferDirectory.path).isEmpty)

        for directory in [applicationSupport, transferDirectory] {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
            #expect(permissions.intValue & 0o022 == 0)
        }
    }
}
