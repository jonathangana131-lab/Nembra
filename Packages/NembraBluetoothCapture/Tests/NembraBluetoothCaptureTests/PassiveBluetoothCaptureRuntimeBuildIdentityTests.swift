import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Capture runtime build identity")
struct PassiveBluetoothCaptureRuntimeBuildIdentityTests {
    private typealias Reader = PassiveBluetoothCaptureRuntimeBuildIdentityReader
    private typealias ReaderError = PassiveBluetoothCaptureRuntimeBuildIdentityError

    private let validCommit = "0123456789abcdef0123456789abcdef01234567"
    private let validBuildInstanceID = "12345678-90ab-cdef-1234-567890abcdef"

    @Test("embedded metadata binds build label, build instance, normalized commit, executable, and raw Info.plist bytes")
    func validEmbeddedMetadata() throws {
        let identity = try Reader.resolveEmbeddedMetadata(
            infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: "Capture Build V14-F1",
                Reader.buildInstanceIDInfoDictionaryKey: validBuildInstanceID.uppercased(),
                Reader.sourceCommitSHAInfoDictionaryKey: validCommit.uppercased()
            ],
            executableData: Data("abc".utf8),
            infoPlistData: Data("plist-a".utf8)
        )

        #expect(identity.buildIdentifier == "Capture Build V14-F1")
        #expect(identity.buildInstanceID == validBuildInstanceID)
        #expect(identity.sourceCommitSHA == validCommit)
        #expect(identity.executableSHA256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(identity.infoPlistSHA256 == "06efe9fe27056463478429afb2c47cc02f0096f2d4ec4282b38df88cb9e4b1b0")
    }

    @Test("different executable bytes cannot retain the same runtime executable identity")
    func executableDigestChangesWithBytes() throws {
        let metadata: [String: Any] = [
            Reader.buildIdentifierInfoDictionaryKey: "Capture Build V14-F1",
            Reader.buildInstanceIDInfoDictionaryKey: validBuildInstanceID,
            Reader.sourceCommitSHAInfoDictionaryKey: validCommit
        ]

        let first = try Reader.resolveEmbeddedMetadata(
            infoDictionary: metadata,
            executableData: Data("binary-a".utf8),
            infoPlistData: Data("plist-a".utf8)
        )
        let second = try Reader.resolveEmbeddedMetadata(
            infoDictionary: metadata,
            executableData: Data("binary-b".utf8),
            infoPlistData: Data("plist-a".utf8)
        )

        #expect(first.buildIdentifier == second.buildIdentifier)
        #expect(first.buildInstanceID == second.buildInstanceID)
        #expect(first.sourceCommitSHA == second.sourceCommitSHA)
        #expect(first.executableSHA256 != second.executableSHA256)
        #expect(first.infoPlistSHA256 == second.infoPlistSHA256)
    }

    @Test("different raw Info.plist bytes cannot retain the same runtime Info.plist identity")
    func infoPlistDigestChangesWithBytes() throws {
        let metadata: [String: Any] = [
            Reader.buildIdentifierInfoDictionaryKey: "Capture Build V14-F1",
            Reader.buildInstanceIDInfoDictionaryKey: validBuildInstanceID,
            Reader.sourceCommitSHAInfoDictionaryKey: validCommit
        ]

        let first = try Reader.resolveEmbeddedMetadata(
            infoDictionary: metadata,
            executableData: Data("binary-a".utf8),
            infoPlistData: Data("plist-a".utf8)
        )
        let second = try Reader.resolveEmbeddedMetadata(
            infoDictionary: metadata,
            executableData: Data("binary-a".utf8),
            infoPlistData: Data("plist-b".utf8)
        )

        #expect(first.buildIdentifier == second.buildIdentifier)
        #expect(first.buildInstanceID == second.buildInstanceID)
        #expect(first.sourceCommitSHA == second.sourceCommitSHA)
        #expect(first.executableSHA256 == second.executableSHA256)
        #expect(first.infoPlistSHA256 != second.infoPlistSHA256)
    }

    @Test("missing build identifier fails closed")
    func missingBuildIdentifier() {
        expectFailure(.missingBuildIdentifier, infoDictionary: [
            Reader.buildInstanceIDInfoDictionaryKey: validBuildInstanceID,
            Reader.sourceCommitSHAInfoDictionaryKey: validCommit
        ])
    }

    @Test("blank or padded build identifiers fail closed instead of being normalized")
    func invalidBuildIdentifierWhitespace() {
        for invalid in ["", " Capture Build V14-F1", "Capture Build V14-F1 ", "\nCapture Build V14-F1"] {
            expectFailure(.invalidBuildIdentifier, infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: invalid,
                Reader.buildInstanceIDInfoDictionaryKey: validBuildInstanceID,
                Reader.sourceCommitSHAInfoDictionaryKey: validCommit
            ])
        }
    }

    @Test("control characters and oversized build identifiers fail closed")
    func invalidBuildIdentifierShape() {
        for invalid in ["Capture\u{0000}Build", String(repeating: "x", count: 129)] {
            expectFailure(.invalidBuildIdentifier, infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: invalid,
                Reader.buildInstanceIDInfoDictionaryKey: validBuildInstanceID,
                Reader.sourceCommitSHAInfoDictionaryKey: validCommit
            ])
        }
    }

    @Test("missing build instance fails closed")
    func missingBuildInstanceID() {
        expectFailure(.missingBuildInstanceID, infoDictionary: [
            Reader.buildIdentifierInfoDictionaryKey: "Capture Build V14-F1",
            Reader.sourceCommitSHAInfoDictionaryKey: validCommit
        ])
    }

    @Test("build instance must be one canonical UUID-shaped identifier")
    func invalidBuildInstanceShape() {
        let invalidValues = [
            String(validBuildInstanceID.dropLast()),
            validBuildInstanceID + "0",
            "g" + String(validBuildInstanceID.dropFirst()),
            " " + String(validBuildInstanceID.dropLast()),
            "1234567890ab-cdef-1234-567890abcdef",
            "HEAD"
        ]

        for invalid in invalidValues {
            expectFailure(.invalidBuildInstanceID, infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: "Capture Build V14-F1",
                Reader.buildInstanceIDInfoDictionaryKey: invalid,
                Reader.sourceCommitSHAInfoDictionaryKey: validCommit
            ])
        }
    }

    @Test("build instance is normalized only for hexadecimal case")
    func buildInstanceNormalization() {
        #expect(Reader.normalizedBuildInstanceID(validBuildInstanceID.uppercased()) == validBuildInstanceID)
        #expect(Reader.normalizedBuildInstanceID(validBuildInstanceID) == validBuildInstanceID)
    }

    @Test("missing source commit fails closed")
    func missingSourceCommit() {
        expectFailure(.missingSourceCommitSHA, infoDictionary: [
            Reader.buildIdentifierInfoDictionaryKey: "Capture Build V14-F1",
            Reader.buildInstanceIDInfoDictionaryKey: validBuildInstanceID
        ])
    }

    @Test("source commit must be one exact full hexadecimal SHA")
    func invalidSourceCommitShape() {
        let invalidValues = [
            String(validCommit.dropLast()),
            validCommit + "0",
            "g" + String(validCommit.dropFirst()),
            " " + String(validCommit.dropLast()),
            "HEAD"
        ]

        for invalid in invalidValues {
            expectFailure(.invalidSourceCommitSHA, infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: "Capture Build V14-F1",
                Reader.buildInstanceIDInfoDictionaryKey: validBuildInstanceID,
                Reader.sourceCommitSHAInfoDictionaryKey: invalid
            ])
        }
    }

    @Test("full hexadecimal source commit is normalized only for case")
    func sourceCommitNormalization() {
        #expect(Reader.normalizedFullGitCommitSHA(validCommit.uppercased()) == validCommit)
        #expect(Reader.normalizedFullGitCommitSHA(validCommit) == validCommit)
    }

    private func expectFailure(
        _ expected: ReaderError,
        infoDictionary: [String: Any],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            _ = try Reader.resolveEmbeddedMetadata(
                infoDictionary: infoDictionary,
                executableData: Data("fixture executable".utf8),
                infoPlistData: Data("fixture info plist".utf8)
            )
            Issue.record("expected build identity production to fail with \(expected)", sourceLocation: sourceLocation)
        } catch let error as ReaderError {
            #expect(error == expected, sourceLocation: sourceLocation)
        } catch {
            Issue.record("unexpected error: \(error)", sourceLocation: sourceLocation)
        }
    }
}
