import Foundation
import Testing
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary Capture authorization inbox custody")
struct AuthenticatedStationaryCaptureAuthorizationInboxTests {
    private typealias Inbox = AuthenticatedStationaryCaptureAuthorizationInbox
    private typealias InboxError = AuthenticatedStationaryCaptureAuthorizationInboxError

    @Test("regular manifest bytes are consumed exactly once")
    func regularManifestIsOneShot() throws {
        try withInbox { directory, inbox in
            let subject = directory.appendingPathComponent(Inbox.installManifestFilename)
            let expected = Data("{\"manifest\":\"fixture\"}".utf8)
            try expected.write(to: subject)

            let received = try inbox.takeInstallManifest()
            #expect(received == expected)
            #expect(!FileManager.default.fileExists(atPath: subject.path))
            #expect(throws: InboxError.missingSubject(Inbox.installManifestFilename)) {
                _ = try inbox.takeInstallManifest()
            }
        }
    }

    @Test("final-component symlinks are rejected before bytes are read")
    func symlinkIsRejected() throws {
        try withInbox { directory, inbox in
            let target = directory.appendingPathComponent("target.json")
            try Data("signed-looking-but-nonauthorizing".utf8).write(to: target)
            let subject = directory.appendingPathComponent(Inbox.authorizationEnvelopeFilename)
            try FileManager.default.createSymbolicLink(at: subject, withDestinationURL: target)

            #expect(throws: InboxError.symbolicLinkRejected(Inbox.authorizationEnvelopeFilename)) {
                _ = try inbox.takeAuthorizationEnvelope()
            }
            #expect(FileManager.default.fileExists(atPath: target.path))
        }
    }

    @Test("multiply linked subjects are rejected instead of consuming an alias")
    func hardLinkIsRejected() throws {
        try withInbox { directory, inbox in
            let target = directory.appendingPathComponent("target.json")
            try Data("manifest".utf8).write(to: target)
            let subject = directory.appendingPathComponent(Inbox.installManifestFilename)
            try FileManager.default.linkItem(at: target, to: subject)

            #expect(throws: InboxError.multipleLinksRejected(Inbox.installManifestFilename)) {
                _ = try inbox.takeInstallManifest()
            }
            #expect(FileManager.default.fileExists(atPath: target.path))
            #expect(FileManager.default.fileExists(atPath: subject.path))
        }
    }

    @Test("byte limit is enforced from the opened file descriptor")
    func oversizedSubjectIsRejected() throws {
        try withInbox { directory, inbox in
            let subject = directory.appendingPathComponent(Inbox.installManifestFilename)
            try Data(
                repeating: 0x41,
                count: 16_385
            ).write(to: subject)

            #expect(throws: InboxError.byteLimitExceeded(Inbox.installManifestFilename)) {
                _ = try inbox.takeInstallManifest()
            }
            #expect(FileManager.default.fileExists(atPath: subject.path))
        }
    }

    @Test("source uses descriptor custody instead of path check then path reopen")
    func sourceContract() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("NembraCaptureAppAuthorization")
            .appendingPathComponent("AuthenticatedStationaryCaptureAuthorizationInbox.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("Darwin.openat(directoryDescriptor"))
        #expect(source.contains("O_NOFOLLOW"))
        #expect(source.components(separatedBy: "Darwin.fstat(descriptor").count - 1 >= 3)
        #expect(source.contains("Darwin.unlinkat(directoryDescriptor"))
        #expect(source.contains("afterRetirement.st_nlink == 0"))
        #expect(!source.contains("Data(contentsOf:"))
        #expect(!source.contains("FileManager.default.removeItem"))
    }

    private func withInbox(
        _ body: (URL, Inbox) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-capture-inbox-tests")
            .appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("FieldAuthorization")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try body(directory, Inbox(directoryURL: directory))
    }
}
