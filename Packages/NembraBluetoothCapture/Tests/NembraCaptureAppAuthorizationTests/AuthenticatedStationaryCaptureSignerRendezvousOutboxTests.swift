import Foundation
import Testing
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary Capture signer rendezvous outbox")
struct AuthenticatedStationaryCaptureSignerRendezvousOutboxTests {
    @Test("publishes the exact canonical rendezvous in the shared app-container directory")
    func publishesCanonicalDocument() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rendezvous = sampleRendezvous(challenge: String(repeating: "a", count: 64))
        let expected = try AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(rendezvous)
        let outbox = AuthenticatedStationaryCaptureSignerRendezvousOutbox(
            applicationSupportURL: root
        )

        try outbox.publish(rendezvous)

        let published = root
            .appendingPathComponent(AuthenticatedStationaryCaptureAuthorizationInbox.directoryName)
            .appendingPathComponent(AuthenticatedStationaryCaptureSignerRendezvousOutbox.rendezvousFilename)
        #expect(try Data(contentsOf: published) == expected)
        let attributes = try FileManager.default.attributesOfItem(atPath: published.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("a new process attempt atomically replaces a stale complete rendezvous")
    func replacesStaleRendezvousWithNewCompleteDocument() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outbox = AuthenticatedStationaryCaptureSignerRendezvousOutbox(
            applicationSupportURL: root
        )
        let old = sampleRendezvous(challenge: String(repeating: "a", count: 64))
        let new = sampleRendezvous(challenge: String(repeating: "b", count: 64))

        try outbox.publish(old)
        try outbox.publish(new)

        let published = root
            .appendingPathComponent(AuthenticatedStationaryCaptureAuthorizationInbox.directoryName)
            .appendingPathComponent(AuthenticatedStationaryCaptureSignerRendezvousOutbox.rendezvousFilename)
        #expect(
            try Data(contentsOf: published)
                == AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(new)
        )
    }

    @Test("a symlinked handoff directory is rejected instead of followed")
    func rejectsSymlinkedHandoffDirectory() throws {
        let root = try temporaryDirectory()
        let elsewhere = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: elsewhere)
        }
        let nembra = root.appendingPathComponent("NembraCapture", isDirectory: true)
        try FileManager.default.createDirectory(at: nembra, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: nembra.appendingPathComponent("FieldAuthorization"),
            withDestinationURL: elsewhere
        )
        let outbox = AuthenticatedStationaryCaptureSignerRendezvousOutbox(
            applicationSupportURL: root
        )

        #expect(throws: (any Error).self) {
            try outbox.publish(sampleRendezvous(challenge: String(repeating: "c", count: 64)))
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: elsewhere
                    .appendingPathComponent(
                        AuthenticatedStationaryCaptureSignerRendezvousOutbox.rendezvousFilename
                    )
                    .path
            )
        )
    }

    @Test("group-writable private handoff directories fail custody validation")
    func rejectsBroadPrivateDirectoryMode() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nembra = root.appendingPathComponent("NembraCapture", isDirectory: true)
        let handoff = nembra.appendingPathComponent("FieldAuthorization", isDirectory: true)
        try FileManager.default.createDirectory(at: handoff, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o770)],
            ofItemAtPath: handoff.path
        )
        let outbox = AuthenticatedStationaryCaptureSignerRendezvousOutbox(
            applicationSupportURL: root
        )

        #expect(throws: AuthenticatedStationaryCaptureSignerRendezvousOutboxError.directoryCustodyRejected("FieldAuthorization")) {
            try outbox.publish(sampleRendezvous(challenge: String(repeating: "d", count: 64)))
        }
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
            .appendingPathComponent("nembra-rendezvous-outbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        return url
    }
}
