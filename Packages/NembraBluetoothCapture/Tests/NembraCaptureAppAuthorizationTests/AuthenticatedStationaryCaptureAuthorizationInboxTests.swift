import CryptoKit
import Foundation
import Testing
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary authorization inbox")
struct AuthenticatedStationaryCaptureAuthorizationInboxTests {
    @Test("digest-committed take returns exact bytes and retires incoming plus commit")
    func exactOneShotTake() throws {
        try withInboxDirectory { directory, inbox in
            let subject = Data("canonical retained install manifest bytes".utf8)
            let incoming = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestIncomingFilename
            )
            let commit = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestCommitFilename
            )
            try subject.write(to: incoming)
            try commitRecord(for: subject).write(to: commit)

            #expect(try inbox.takeInstallManifest() == subject)
            #expect(!FileManager.default.fileExists(atPath: incoming.path))
            #expect(!FileManager.default.fileExists(atPath: commit.path))
            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestFilename
            )) {
                _ = try inbox.takeInstallManifest()
            }
        }
    }

    @Test("partial completion record is retryable and never consumes incoming bytes")
    func partialCommitIsRetryable() throws {
        try withInboxDirectory { directory, inbox in
            let subject = Data("signed envelope bytes still arriving".utf8)
            let incoming = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeIncomingFilename
            )
            let commit = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeCommitFilename
            )
            try subject.write(to: incoming)
            try Data(String(repeating: "a", count: 20).utf8).write(to: commit)

            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(
                AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeFilename
            )) {
                _ = try inbox.takeAuthorizationEnvelope()
            }
            #expect(FileManager.default.fileExists(atPath: incoming.path))
            #expect(FileManager.default.fileExists(atPath: commit.path))
        }
    }

    @Test("stale digest is retryable until the later commit matches the stable incoming bytes")
    func staleDigestIsRetryable() throws {
        try withInboxDirectory { directory, inbox in
            let subject = Data("new signed envelope bytes".utf8)
            let incoming = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeIncomingFilename
            )
            let commit = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeCommitFilename
            )
            try subject.write(to: incoming)
            try commitRecord(for: Data("old envelope".utf8)).write(to: commit)

            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(
                AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeFilename
            )) {
                _ = try inbox.takeAuthorizationEnvelope()
            }
            #expect(FileManager.default.fileExists(atPath: incoming.path))
            #expect(FileManager.default.fileExists(atPath: commit.path))

            try FileManager.default.removeItem(at: commit)
            try commitRecord(for: subject).write(to: commit)
            #expect(try inbox.takeAuthorizationEnvelope() == subject)
            #expect(!FileManager.default.fileExists(atPath: incoming.path))
            #expect(!FileManager.default.fileExists(atPath: commit.path))
        }
    }

    @Test("symbolic-link substitution is rejected without consuming the target")
    func symbolicLinkRejected() throws {
        try withInboxDirectory { directory, inbox in
            let subject = Data("signed envelope target".utf8)
            let target = directory.appendingPathComponent("target.json")
            try subject.write(to: target)
            let incoming = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeIncomingFilename
            )
            let commit = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeCommitFilename
            )
            try FileManager.default.createSymbolicLink(at: incoming, withDestinationURL: target)
            try commitRecord(for: subject).write(to: commit)

            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.symbolicLinkRejected(
                AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeIncomingFilename
            )) {
                _ = try inbox.takeAuthorizationEnvelope()
            }
            #expect(FileManager.default.fileExists(atPath: target.path))
        }
    }

    @Test("hard-linked incoming subject is rejected instead of treating shared bytes as one-shot")
    func hardLinkRejected() throws {
        try withInboxDirectory { directory, inbox in
            let subject = Data("retained manifest target".utf8)
            let target = directory.appendingPathComponent("target.json")
            try subject.write(to: target)
            let incoming = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestIncomingFilename
            )
            let commit = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestCommitFilename
            )
            try FileManager.default.linkItem(at: target, to: incoming)
            try commitRecord(for: subject).write(to: commit)

            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.multipleLinksRejected(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestIncomingFilename
            )) {
                _ = try inbox.takeInstallManifest()
            }
            #expect(FileManager.default.fileExists(atPath: target.path))
            #expect(FileManager.default.fileExists(atPath: incoming.path))
        }
    }

    @Test("committed subject beyond package byte limit fails before data promotion")
    func oversizedSubjectRejected() throws {
        try withInboxDirectory { directory, inbox in
            let subject = Data(repeating: 0x41, count: 16_385)
            let incoming = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestIncomingFilename
            )
            let commit = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestCommitFilename
            )
            try subject.write(to: incoming)
            try commitRecord(for: subject).write(to: commit)

            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.byteLimitExceeded(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestIncomingFilename
            )) {
                _ = try inbox.takeInstallManifest()
            }
            #expect(FileManager.default.fileExists(atPath: incoming.path))
            #expect(FileManager.default.fileExists(atPath: commit.path))
        }
    }

    @Test("source consumes only stable digest-committed bytes through no-follow descriptors")
    func sourceContract() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/NembraCaptureAppAuthorization/AuthenticatedStationaryCaptureAuthorizationInbox.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("import CryptoKit"))
        #expect(source.contains("retained-install-manifest.incoming"))
        #expect(source.contains("retained-install-manifest.commit"))
        #expect(source.contains("authorization-envelope.incoming"))
        #expect(source.contains("authorization-envelope.commit"))
        #expect(source.contains("commitRecordByteCount = 65"))
        #expect(source.contains("guard sha256Hex(data) == expectedSHA256"))
        #expect(source.contains("O_RDONLY | O_NOFOLLOW | O_CLOEXEC"))
        #expect(source.contains("Darwin.unlinkat(directoryFD, incomingFilename, 0)"))
        #expect(source.contains("Darwin.unlinkat(directoryFD, commitFilename, 0)"))
        #expect(source.contains("incomingAfterUnlink.st_nlink == 0"))
        #expect(source.contains("commitAfterUnlink.st_nlink == 0"))
        #expect(!source.contains("Data(contentsOf: fileURL"))
        #expect(!source.contains("resourceValues(forKeys:"))
    }

    private func commitRecord(for data: Data) -> Data {
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return Data((digest + "\n").utf8)
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
