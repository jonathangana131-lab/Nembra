import Foundation
import Testing
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary Capture signer rendezvous outbox")
struct AuthenticatedStationaryCaptureSignerRendezvousOutboxTests {
    @Test("publishes exact canonical rendezvous with owner-only file mode")
    func publishesCanonicalDocument() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rendezvous = sampleRendezvous(challenge: String(repeating: "a", count: 64))
        let expected = try AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(rendezvous)
        let outbox = AuthenticatedStationaryCaptureSignerRendezvousOutbox(applicationSupportURL: root)

        try outbox.publish(rendezvous)

        let published = publishedURL(root: root)
        #expect(try Data(contentsOf: published) == expected)
        let attributes = try FileManager.default.attributesOfItem(atPath: published.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("new process attempt atomically replaces stale complete rendezvous")
    func replacesStaleRendezvousWithNewCompleteDocument() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outbox = AuthenticatedStationaryCaptureSignerRendezvousOutbox(applicationSupportURL: root)
        let old = sampleRendezvous(challenge: String(repeating: "a", count: 64))
        let new = sampleRendezvous(challenge: String(repeating: "b", count: 64))

        try outbox.publish(old)
        try outbox.publish(new)

        #expect(
            try Data(contentsOf: publishedURL(root: root))
                == AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(new)
        )
    }

    @Test("symlinked handoff directory is rejected instead of followed")
    func rejectsSymlinkedHandoffDirectory() throws {
        let root = try temporaryDirectory()
        let elsewhere = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: elsewhere)
        }
        let nembra = root.appendingPathComponent("NembraCapture", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nembra,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        try FileManager.default.createSymbolicLink(
            at: nembra.appendingPathComponent("FieldAuthorization"),
            withDestinationURL: elsewhere
        )
        let outbox = AuthenticatedStationaryCaptureSignerRendezvousOutbox(applicationSupportURL: root)

        do {
            try outbox.publish(sampleRendezvous(challenge: String(repeating: "c", count: 64)))
            Issue.record("expected symlinked handoff directory to be rejected")
        } catch {
            // Darwin may report ELOOP or ENOTDIR for O_DIRECTORY|O_NOFOLLOW; success is forbidden.
        }
        #expect(!FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent(
            AuthenticatedStationaryCaptureSignerRendezvousOutbox.rendezvousFilename
        ).path))
    }

    @Test("group-writable private handoff directory fails custody validation")
    func rejectsBroadPrivateDirectoryMode() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let handoff = root
            .appendingPathComponent("NembraCapture", isDirectory: true)
            .appendingPathComponent("FieldAuthorization", isDirectory: true)
        try FileManager.default.createDirectory(
            at: handoff,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o770)],
            ofItemAtPath: handoff.path
        )
        let outbox = AuthenticatedStationaryCaptureSignerRendezvousOutbox(applicationSupportURL: root)

        #expect(
            throws: AuthenticatedStationaryCaptureSignerRendezvousOutboxError
                .directoryCustodyRejected("FieldAuthorization")
        ) {
            try outbox.publish(sampleRendezvous(challenge: String(repeating: "d", count: 64)))
        }
    }

    private func publishedURL(root: URL) -> URL {
        root
            .appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.directoryName,
                isDirectory: true
            )
            .appendingPathComponent(
                AuthenticatedStationaryCaptureSignerRendezvousOutbox.rendezvousFilename
            )
    }

    private func sampleRendezvous(
        challenge: String
    ) -> AuthenticatedStationaryCaptureAppSession.SignerRendezvous {
        .init(
            challengeSHA256: challenge,
            startedAtWallClockUnixMilliseconds: 2_000_000,
            startedAtUptimeNanoseconds: 1_000_000_000,
            procedureID: "ES80-AUTHENTICATED-STATIONARY-v1"
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "nembra-rendezvous-outbox-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        return url
    }
}
