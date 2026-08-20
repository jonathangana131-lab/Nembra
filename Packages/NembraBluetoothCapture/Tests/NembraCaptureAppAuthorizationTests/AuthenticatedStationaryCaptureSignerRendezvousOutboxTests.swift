import Foundation
import Testing
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary Capture signer rendezvous outbox")
struct AuthenticatedStationaryCaptureSignerRendezvousOutboxTests {
    @Test("publish is canonical owner-only no-replace and retirement is one-shot")
    func publishAndRetire() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outbox = AuthenticatedStationaryCaptureSignerRendezvousOutbox(
            applicationSupportURL: root
        )
        let rendezvous = makeRendezvous()
        let expected = try AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(rendezvous)

        #expect(try outbox.publish(rendezvous) == expected)
        let file = root
            .appendingPathComponent(AuthenticatedStationaryCaptureAuthorizationInbox.directoryName)
            .appendingPathComponent(AuthenticatedStationaryCaptureSignerRendezvousOutbox.filename)
        #expect(try Data(contentsOf: file) == expected)

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)

        #expect(throws: AuthenticatedStationaryCaptureSignerRendezvousOutboxError.alreadyPublished) {
            _ = try outbox.publish(rendezvous)
        }

        try outbox.retirePublishedRendezvous()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(throws: AuthenticatedStationaryCaptureSignerRendezvousOutboxError.retirementFailed) {
            try outbox.retirePublishedRendezvous()
        }
    }

    @Test("symlinked application-support root is rejected before directory traversal")
    func rejectsSymlinkedApplicationSupportRoot() throws {
        let parent = try temporaryDirectory()
        let elsewhere = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: parent)
            try? FileManager.default.removeItem(at: elsewhere)
        }
        let linkedRoot = parent.appendingPathComponent("ApplicationSupport")
        try FileManager.default.createSymbolicLink(
            at: linkedRoot,
            withDestinationURL: elsewhere
        )
        let outbox = AuthenticatedStationaryCaptureSignerRendezvousOutbox(
            applicationSupportURL: linkedRoot
        )

        #expect(throws: AuthenticatedStationaryCaptureSignerRendezvousOutboxError.applicationSupportUnavailable) {
            _ = try outbox.publish(makeRendezvous())
        }
    }

    @Test("symlinked app-controlled directory is rejected")
    func rejectsSymlinkedDirectory() throws {
        let root = try temporaryDirectory()
        let elsewhere = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: elsewhere)
        }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("NembraCapture"),
            withDestinationURL: elsewhere
        )
        let outbox = AuthenticatedStationaryCaptureSignerRendezvousOutbox(
            applicationSupportURL: root
        )

        #expect(throws: AuthenticatedStationaryCaptureSignerRendezvousOutboxError.directoryCustodyRejected("NembraCapture")) {
            _ = try outbox.publish(makeRendezvous())
        }
    }

    @Test("hard-linked published subject cannot be retired as one-shot")
    func rejectsHardLinkedSubjectRetirement() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outbox = AuthenticatedStationaryCaptureSignerRendezvousOutbox(
            applicationSupportURL: root
        )
        _ = try outbox.publish(makeRendezvous())

        let directory = root.appendingPathComponent(
            AuthenticatedStationaryCaptureAuthorizationInbox.directoryName
        )
        let file = directory.appendingPathComponent(
            AuthenticatedStationaryCaptureSignerRendezvousOutbox.filename
        )
        try FileManager.default.linkItem(
            at: file,
            to: directory.appendingPathComponent("second-link.json")
        )

        #expect(throws: AuthenticatedStationaryCaptureSignerRendezvousOutboxError.subjectCustodyRejected) {
            try outbox.retirePublishedRendezvous()
        }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("source binds publication success to the descriptor-backed pathname inode")
    func sourcePinsCustodyContract() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/NembraCaptureAppAuthorization/AuthenticatedStationaryCaptureSignerRendezvousOutbox.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC"))
        #expect(source.contains("Darwin.mkdirat"))
        #expect(source.contains("Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)"))
        #expect(source.contains("Darwin.fstatat(directoryFD, Self.filename, &published, AT_SYMLINK_NOFOLLOW)"))
        #expect(source.contains("pathStillNamesDescriptor(directoryFD: directoryFD, descriptor: descriptor)"))
        #expect(source.contains("Darwin.unlinkat(directoryFD, Self.filename, 0)"))
        #expect(source.contains("after.st_nlink == 0"))
        #expect(!source.contains("write(to:"))
        #expect(!source.contains("removeItem"))
    }

    private func makeRendezvous() -> AuthenticatedStationaryCaptureAppSession.SignerRendezvous {
        .init(
            challengeSHA256: String(repeating: "a", count: 64),
            startedAtWallClockUnixMilliseconds: 2_000_000,
            startedAtUptimeNanoseconds: 1_000_000_000,
            procedureID: "ES80-AUTHENTICATED-STATIONARY-v1"
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }
}
