import Foundation
import NembraBluetoothCapture
import Testing
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary Capture authorization inbox")
struct AuthenticatedStationaryCaptureAuthorizationInboxTests {
    private typealias Inbox = AuthenticatedStationaryCaptureAuthorizationInbox
    private typealias InboxError = AuthenticatedStationaryCaptureAuthorizationInboxError

    @Test("taking a retained manifest is one-shot and byte exact")
    func retainedManifestIsOneShot() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = Inbox(directoryURL: root)
        let subject = Data("canonical-retained-manifest".utf8)
        let path = root.appendingPathComponent(Inbox.installManifestFilename)
        try subject.write(to: path)

        #expect(try inbox.takeInstallManifest() == subject)
        #expect(!FileManager.default.fileExists(atPath: path.path))
        #expect(throws: InboxError.missingSubject(Inbox.installManifestFilename)) {
            _ = try inbox.takeInstallManifest()
        }
    }

    @Test("manifest and later authorization envelope remain separate one-shot subjects")
    func stableAndPostChallengeSubjectsStaySeparate() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = Inbox(directoryURL: root)
        let manifest = Data("stable-manifest".utf8)
        let envelope = Data("post-challenge-envelope".utf8)
        let manifestPath = root.appendingPathComponent(Inbox.installManifestFilename)
        let envelopePath = root.appendingPathComponent(Inbox.authorizationEnvelopeFilename)
        try manifest.write(to: manifestPath)
        try envelope.write(to: envelopePath)

        #expect(try inbox.takeInstallManifest() == manifest)
        #expect(!FileManager.default.fileExists(atPath: manifestPath.path))
        #expect(FileManager.default.fileExists(atPath: envelopePath.path))
        #expect(try inbox.takeAuthorizationEnvelope() == envelope)
        #expect(!FileManager.default.fileExists(atPath: envelopePath.path))
    }

    @Test("symbolic links are rejected without consuming their target")
    func symbolicLinkIsRejected() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = Inbox(directoryURL: root)
        let target = root.appendingPathComponent("outside-subject.json")
        let subject = Data("must-not-be-followed".utf8)
        try subject.write(to: target)
        let link = root.appendingPathComponent(Inbox.installManifestFilename)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(throws: InboxError.symbolicLinkRejected(Inbox.installManifestFilename)) {
            _ = try inbox.takeInstallManifest()
        }
        #expect(try Data(contentsOf: target) == subject)
        #expect(FileManager.default.fileExists(atPath: link.path))
    }

    @Test("directories and empty subjects fail closed")
    func nonRegularAndEmptySubjectsFailClosed() throws {
        let directoryRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryRoot) }
        let directoryInbox = Inbox(directoryURL: directoryRoot)
        let directorySubject = directoryRoot.appendingPathComponent(Inbox.installManifestFilename)
        try FileManager.default.createDirectory(
            at: directorySubject,
            withIntermediateDirectories: false
        )
        #expect(throws: InboxError.nonRegularFile(Inbox.installManifestFilename)) {
            _ = try directoryInbox.takeInstallManifest()
        }

        let emptyRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        let emptyInbox = Inbox(directoryURL: emptyRoot)
        try Data().write(
            to: emptyRoot.appendingPathComponent(Inbox.authorizationEnvelopeFilename)
        )
        #expect(throws: InboxError.byteLimitExceeded(Inbox.authorizationEnvelopeFilename)) {
            _ = try emptyInbox.takeAuthorizationEnvelope()
        }
    }

    @Test("manifest and envelope byte limits are enforced before bytes are returned")
    func byteLimitsFailClosed() throws {
        let manifestRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: manifestRoot) }
        let manifestInbox = Inbox(directoryURL: manifestRoot)
        try Data(
            repeating: 0x41,
            count: AuthenticatedStationaryCaptureInstallManifestVerifier.maximumManifestByteCount + 1
        ).write(to: manifestRoot.appendingPathComponent(Inbox.installManifestFilename))
        #expect(throws: InboxError.byteLimitExceeded(Inbox.installManifestFilename)) {
            _ = try manifestInbox.takeInstallManifest()
        }

        let envelopeRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: envelopeRoot) }
        let envelopeInbox = Inbox(directoryURL: envelopeRoot)
        try Data(
            repeating: 0x42,
            count: AuthenticatedStationaryCaptureFieldAuthorizationVerifier.maximumEnvelopeByteCount + 1
        ).write(to: envelopeRoot.appendingPathComponent(Inbox.authorizationEnvelopeFilename))
        #expect(throws: InboxError.byteLimitExceeded(Inbox.authorizationEnvelopeFilename)) {
            _ = try envelopeInbox.takeAuthorizationEnvelope()
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NembraCaptureAuthorizationInboxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}
