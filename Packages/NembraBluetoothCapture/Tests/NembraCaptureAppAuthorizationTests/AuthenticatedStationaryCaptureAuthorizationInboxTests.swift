import CryptoKit
import Foundation
import Testing
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary authorization inbox")
struct AuthenticatedStationaryCaptureAuthorizationInboxTests {
    @Test("commit record publishes exact bytes once and retires both entries")
    func exactOneShotCommittedTake() throws {
        try withInboxDirectory { directory, inbox in
            let subject = Data("canonical retained install manifest bytes".utf8)
            let publication = try publish(
                subject,
                stem: "retained-install-manifest",
                commitFilename: AuthenticatedStationaryCaptureAuthorizationInbox
                    .installManifestCommitFilename,
                in: directory
            )

            #expect(try inbox.takeInstallManifest() == subject)
            #expect(!FileManager.default.fileExists(atPath: publication.staged.path))
            #expect(!FileManager.default.fileExists(atPath: publication.commit.path))
            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestFilename
            )) {
                _ = try inbox.takeInstallManifest()
            }
        }
    }

    @Test("partial commit is not promoted or retired and becomes consumable after completion")
    func partialCommitIsRetryable() throws {
        try withInboxDirectory { directory, inbox in
            let subject = Data("signed envelope bytes".utf8)
            let digest = sha256Hex(subject)
            let staged = directory.appendingPathComponent(
                "authorization-envelope.\(digest).staged"
            )
            let commit = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox
                    .authorizationEnvelopeCommitFilename
            )
            try subject.write(to: staged)
            try Data("NEMBRA-FIELD-HANDOFF-V1\nauthorization-envelope".utf8)
                .write(to: commit)

            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(
                AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeFilename
            )) {
                _ = try inbox.takeAuthorizationEnvelope()
            }
            #expect(FileManager.default.fileExists(atPath: staged.path))
            #expect(FileManager.default.fileExists(atPath: commit.path))

            try commitData(subject, stem: "authorization-envelope").write(to: commit)
            #expect(try inbox.takeAuthorizationEnvelope() == subject)
            #expect(!FileManager.default.fileExists(atPath: staged.path))
            #expect(!FileManager.default.fileExists(atPath: commit.path))
        }
    }

    @Test("commit cannot redirect intake outside its digest-addressed staging name")
    func stagingNameInjectionIsNotPublished() throws {
        try withInboxDirectory { directory, inbox in
            let subject = Data("manifest".utf8)
            let digest = sha256Hex(subject)
            let target = directory.appendingPathComponent("target.json")
            try subject.write(to: target)
            let commit = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestCommitFilename
            )
            let injected = "NEMBRA-FIELD-HANDOFF-V1\n../target.json\n\(subject.count)\n\(digest)\n"
            try Data(injected.utf8).write(to: commit)

            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.missingSubject(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestFilename
            )) {
                _ = try inbox.takeInstallManifest()
            }
            #expect(FileManager.default.fileExists(atPath: target.path))
            #expect(FileManager.default.fileExists(atPath: commit.path))
        }
    }

    @Test("digest mismatch fails closed without retiring the staged subject")
    func committedDigestMismatchRejected() throws {
        try withInboxDirectory { directory, inbox in
            let committed = Data("expected envelope".utf8)
            let digest = sha256Hex(committed)
            let staged = directory.appendingPathComponent(
                "authorization-envelope.\(digest).staged"
            )
            try Data("different envelope".utf8).write(to: staged)
            let commit = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox
                    .authorizationEnvelopeCommitFilename
            )
            try commitData(committed, stem: "authorization-envelope").write(to: commit)

            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError
                .committedByteCountMismatch(
                    AuthenticatedStationaryCaptureAuthorizationInbox.authorizationEnvelopeFilename
                )) {
                _ = try inbox.takeAuthorizationEnvelope()
            }
            #expect(FileManager.default.fileExists(atPath: staged.path))
            #expect(FileManager.default.fileExists(atPath: commit.path))
        }
    }

    @Test("symbolic-link staging substitution is rejected without consuming the target")
    func symbolicLinkRejected() throws {
        try withInboxDirectory { directory, inbox in
            let subject = Data("signed envelope target".utf8)
            let digest = sha256Hex(subject)
            let target = directory.appendingPathComponent("target.json")
            try subject.write(to: target)
            let staged = directory.appendingPathComponent(
                "authorization-envelope.\(digest).staged"
            )
            try FileManager.default.createSymbolicLink(at: staged, withDestinationURL: target)
            let commit = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox
                    .authorizationEnvelopeCommitFilename
            )
            try commitData(subject, stem: "authorization-envelope").write(to: commit)

            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.symbolicLinkRejected(
                staged.lastPathComponent
            )) {
                _ = try inbox.takeAuthorizationEnvelope()
            }
            #expect(FileManager.default.fileExists(atPath: target.path))
            #expect(FileManager.default.fileExists(atPath: commit.path))
        }
    }

    @Test("hard-linked staged subject is rejected instead of treating shared inode bytes as one-shot")
    func hardLinkRejected() throws {
        try withInboxDirectory { directory, inbox in
            let subject = Data("retained manifest target".utf8)
            let digest = sha256Hex(subject)
            let target = directory.appendingPathComponent("target.json")
            try subject.write(to: target)
            let staged = directory.appendingPathComponent(
                "retained-install-manifest.\(digest).staged"
            )
            try FileManager.default.linkItem(at: target, to: staged)
            let commit = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestCommitFilename
            )
            try commitData(subject, stem: "retained-install-manifest").write(to: commit)

            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.multipleLinksRejected(
                staged.lastPathComponent
            )) {
                _ = try inbox.takeInstallManifest()
            }
            #expect(FileManager.default.fileExists(atPath: target.path))
            #expect(FileManager.default.fileExists(atPath: staged.path))
            #expect(FileManager.default.fileExists(atPath: commit.path))
        }
    }

    @Test("staged subject beyond package byte limit fails before data promotion")
    func oversizedSubjectRejected() throws {
        try withInboxDirectory { directory, inbox in
            let subject = Data(repeating: 0x41, count: 16_385)
            let digest = sha256Hex(subject)
            let staged = directory.appendingPathComponent(
                "retained-install-manifest.\(digest).staged"
            )
            try subject.write(to: staged)
            let commit = directory.appendingPathComponent(
                AuthenticatedStationaryCaptureAuthorizationInbox.installManifestCommitFilename
            )
            let claimedCount = 16_384
            let marker = "NEMBRA-FIELD-HANDOFF-V1\nretained-install-manifest.\(digest).staged\n\(claimedCount)\n\(digest)\n"
            try Data(marker.utf8).write(to: commit)

            #expect(throws: AuthenticatedStationaryCaptureAuthorizationInboxError.byteLimitExceeded(
                staged.lastPathComponent
            )) {
                _ = try inbox.takeInstallManifest()
            }
            #expect(FileManager.default.fileExists(atPath: staged.path))
            #expect(FileManager.default.fileExists(atPath: commit.path))
        }
    }

    @Test("source requires commit-before-stage retirement and descriptor-bound custody")
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
        #expect(source.contains("NEMBRA-FIELD-HANDOFF-V1"))
        #expect(source.contains("O_RDONLY | O_NOFOLLOW | O_CLOEXEC"))
        #expect(source.contains("Darwin.fstat(descriptor, &value)"))
        #expect(source.contains("value.st_nlink == 1"))
        #expect(source.contains("sameSnapshot(before, after)"))
        #expect(source.contains("Self.sha256Hex(staged.data) == commit.sha256"))
        #expect(source.contains("after.st_nlink == 0"))
        #expect(source.contains("sameInode(before, after)"))
        #expect(source.contains("commitFilename: Self.installManifestCommitFilename"))
        #expect(source.contains("commitFilename: Self.authorizationEnvelopeCommitFilename"))
        let retireComment = source.firstIndex(of: "Retire the commit first")
        let commitUnlink = source.firstIndex(of: "filename: commitFilename")
        let stagedUnlink = source.firstIndex(of: "filename: commit.stagedFilename")
        #expect(retireComment != nil)
        #expect(commitUnlink != nil)
        #expect(stagedUnlink != nil)
        #expect(!source.contains("Data(contentsOf: fileURL"))
        #expect(!source.contains("resourceValues(forKeys:"))
    }

    private struct Publication {
        let staged: URL
        let commit: URL
    }

    private func publish(
        _ subject: Data,
        stem: String,
        commitFilename: String,
        in directory: URL
    ) throws -> Publication {
        let digest = sha256Hex(subject)
        let staged = directory.appendingPathComponent("\(stem).\(digest).staged")
        let commit = directory.appendingPathComponent(commitFilename)
        try subject.write(to: staged)
        try commitData(subject, stem: stem).write(to: commit)
        return Publication(staged: staged, commit: commit)
    }

    private func commitData(_ subject: Data, stem: String) -> Data {
        let digest = sha256Hex(subject)
        return Data(
            "NEMBRA-FIELD-HANDOFF-V1\n\(stem).\(digest).staged\n\(subject.count)\n\(digest)\n".utf8
        )
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

private extension String {
    func firstIndex(of substring: String) -> String.Index? {
        range(of: substring)?.lowerBound
    }
}