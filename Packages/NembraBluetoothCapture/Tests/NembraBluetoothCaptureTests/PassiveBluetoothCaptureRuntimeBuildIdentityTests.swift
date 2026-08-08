import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Capture runtime build identity")
struct PassiveBluetoothCaptureRuntimeBuildIdentityTests {
    private typealias Reader = PassiveBluetoothCaptureRuntimeBuildIdentityReader
    private typealias ReaderError = PassiveBluetoothCaptureRuntimeBuildIdentityError

    private let validCommit = "0123456789abcdef0123456789abcdef01234567"

    @Test("embedded metadata binds build label, normalized commit, and exact executable bytes")
    func validEmbeddedMetadata() throws {
        let identity = try Reader.resolveEmbeddedMetadata(
            infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: "Capture Build V14-F1",
                Reader.sourceCommitSHAInfoDictionaryKey: validCommit.uppercased()
            ],
            executableData: Data("abc".utf8)
        )

        #expect(identity.buildIdentifier == "Capture Build V14-F1")
        #expect(identity.sourceCommitSHA == validCommit)
        #expect(identity.executableSHA256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("different executable bytes cannot retain the same runtime executable identity")
    func executableDigestChangesWithBytes() throws {
        let metadata: [String: Any] = [
            Reader.buildIdentifierInfoDictionaryKey: "Capture Build V14-F1",
            Reader.sourceCommitSHAInfoDictionaryKey: validCommit
        ]

        let first = try Reader.resolveEmbeddedMetadata(
            infoDictionary: metadata,
            executableData: Data("binary-a".utf8)
        )
        let second = try Reader.resolveEmbeddedMetadata(
            infoDictionary: metadata,
            executableData: Data("binary-b".utf8)
        )

        #expect(first.buildIdentifier == second.buildIdentifier)
        #expect(first.sourceCommitSHA == second.sourceCommitSHA)
        #expect(first.executableSHA256 != second.executableSHA256)
    }

    @Test("missing build identifier fails closed")
    func missingBuildIdentifier() {
        expectFailure(.missingBuildIdentifier, infoDictionary: [
            Reader.sourceCommitSHAInfoDictionaryKey: validCommit
        ])
    }

    @Test("blank or padded build identifiers fail closed instead of being normalized")
    func invalidBuildIdentifierWhitespace() {
        for invalid in ["", " Capture Build V14-F1", "Capture Build V14-F1 ", "\nCapture Build V14-F1"] {
            expectFailure(.invalidBuildIdentifier, infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: invalid,
                Reader.sourceCommitSHAInfoDictionaryKey: validCommit
            ])
        }
    }

    @Test("control characters and oversized build identifiers fail closed")
    func invalidBuildIdentifierShape() {
        for invalid in ["Capture\u{0000}Build", String(repeating: "x", count: 129)] {
            expectFailure(.invalidBuildIdentifier, infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: invalid,
                Reader.sourceCommitSHAInfoDictionaryKey: validCommit
            ])
        }
    }

    @Test("missing source commit fails closed")
    func missingSourceCommit() {
        expectFailure(.missingSourceCommitSHA, infoDictionary: [
            Reader.buildIdentifierInfoDictionaryKey: "Capture Build V14-F1"
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
                executableData: Data("fixture executable".utf8)
            )
            Issue.record("expected build identity production to fail with \(expected)", sourceLocation: sourceLocation)
        } catch let error as ReaderError {
            #expect(error == expected, sourceLocation: sourceLocation)
        } catch {
            Issue.record("unexpected error: \(error)", sourceLocation: sourceLocation)
        }
    }
}
