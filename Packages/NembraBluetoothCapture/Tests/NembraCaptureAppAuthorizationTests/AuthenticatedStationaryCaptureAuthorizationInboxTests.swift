import Foundation
import Testing
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary authorization inbox")
struct AuthenticatedStationaryCaptureAuthorizationInboxTests {
    @Test("descriptor-bound take returns exact bytes and retires the handoff")
    func exactOneShotTake() throws {
        try withInboxDirectory { directory, inbox in
            let subject = Data("canonical retained install manifest bytes".utf8)
            let url = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestFilename
            )
            try subject.write(to: url, options: .atomic)

            #expect(try inbox.takeInstallManifest() == subject)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestFilename
            )) {
                _ = try inbox.takeInstallManifest()
            }
        }
    }

    @Test("symbolic-link substitution is rejected without consuming the target")
    func symbolicLinkRejected() throws {
        try withInboxDirectory { directory, inbox in
            let target = directory.appendingPathComponent("target.json")
            try Data("signed envelope target".utf8).write(to: target)
            let handoff = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeFilename
            )
            try FileManager.default.createSymbolicLink(at: handoff, withDestinationURL: target)

            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.symbolicLinkRejected(
                AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeFilename
            )) {
                _ = try inbox.takeAuthorizationEnvelope()
            }
            #expect(FileManager.default.fileExists(atPath: target.path))
        }
    }

    @Test("hard-linked subject is rejected instead of treating shared inode bytes as one-shot")
    func hardLinkRejected() throws {
        try withInboxDirectory { directory, inbox in
            let target = directory.appendingPathComponent("target.json")
            try Data("retained manifest target".utf8).write(to: target)
            let handoff = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestFilename
            )
            try FileManager.default.linkItem(at: target, to: handoff)

            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.multipleLinksRejected(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestFilename
            )) {
                _ = try inbox.takeInstallManifest()
            }
            #expect(FileManager.default.fileExists(atPath: target.path))
            #expect(FileManager.default.fileExists(atPath: handoff.path))
        }
    }

    @Test("subject beyond package byte limit fails before data promotion")
    func oversizedSubjectRejected() throws {
        try withInboxDirectory { directory, inbox in
            let url = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestFilename
            )
            let count = 16_385
            try Data(repeating: 0x41, count: count).write(to: url)

            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.byteLimitExceeded(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestFilename
            )) {
                _ = try inbox.takeInstallManifest()
            }
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("source reads and retires authority bytes through one no-follow descriptor")
    func sourceContract() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/NembraCaptureAppAuthorization/AuthenticatedStationaryCaptureAuthorizationInbox.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("O_RDONLY | O_NOFOLLOW | O_CLOEXEC"))
        #expect(source.contains("Darwin.fstat(descriptor, &before)"))
        #expect(source.contains("Darwin.fstat(descriptor, &afterRead)"))
        #expect(source.contains("before.st_nlink == 1"))
        #expect(source.contains("sameSnapshot(before, afterRead)"))
        #expect(source.contains("Darwin.unlinkat(directoryFD, filename, 0)"))
        #expect(source.contains("afterUnlink.st_nlink == 0"))
        #expect(source.contains("sameInode(before, afterUnlink)"))
        #expect(!source.contains("sameSnapshotExceptLinkCount"))
        #expect(!source.contains("Data(contentsOf: fileURL"))
        #expect(!source.contains("resourceValues(forKeys:"))
    }

    private func withInboxDirectory(
        _ body: (URL, AuthenticatedStationaryCaptureAuthorizationInbox) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-authorization-inbox-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(
            directory,
            AuthenticatedStationaryCaptureAuthorizationInbox(directoryURL: directory)
        )
    }
}
