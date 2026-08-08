import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Capture trusted build preflight")
struct PassiveBluetoothCaptureTrustedBuildPreflightTests {
    private typealias RecordReader = PassiveBluetoothCaptureTrustedBuildRecordReader
    private typealias RecordError = PassiveBluetoothCaptureTrustedBuildRecordError
    private typealias PreflightError = PassiveBluetoothCaptureBuildPreflightError

    private let buildIdentifier = "Capture Build V14-F1"
    private let sourceCommit = "0123456789abcdef0123456789abcdef01234567"
    private let abcSHA256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    @Test("closed-world trusted record binds exact runtime bytes, commit, recipe, and procedure")
    func exactRuntimeBinding() throws {
        let record = try decodeRecord()
        let runtime = try makeRuntime(
            buildIdentifier: buildIdentifier,
            sourceCommit: sourceCommit.uppercased(),
            executableBytes: Data("abc".utf8)
        )

        let binding = try PassiveBluetoothCaptureBuildPreflight.evaluate(
            runtimeIdentity: runtime,
            trustedRecord: record
        )

        #expect(binding.buildIdentifier == buildIdentifier)
        #expect(binding.sourceCommitSHA == sourceCommit)
        #expect(binding.executableSHA256 == abcSHA256)
        #expect(binding.experimentRecipeID == .es80FingerprintV1)
        #expect(binding.procedureVersion == "V14")
    }

    @Test("unknown trusted-record claims fail closed")
    func unknownFieldsFailClosed() {
        let json = """
        {
          "schemaVersion": 1,
          "buildIdentifier": "\(buildIdentifier)",
          "sourceCommitSHA": "\(sourceCommit)",
          "executableSHA256": "\(abcSHA256)",
          "experimentRecipeID": "ES80-FINGERPRINT-v1",
          "procedureVersion": "V14",
          "physicallyVerified": true
        }
        """

        expectRecordFailure(
            .unexpectedTrustedBuildRecordFields(["physicallyVerified"]),
            data: Data(json.utf8)
        )
    }

    @Test("missing required trusted-record fields fail closed")
    func missingFieldFailsClosed() {
        let json = """
        {
          "schemaVersion": 1,
          "buildIdentifier": "\(buildIdentifier)",
          "sourceCommitSHA": "\(sourceCommit)",
          "executableSHA256": "\(abcSHA256)",
          "experimentRecipeID": "ES80-FINGERPRINT-v1"
        }
        """

        expectRecordFailure(.malformedTrustedBuildRecord, data: Data(json.utf8))
    }

    @Test("schema, recipe, and procedure are fixed field-build contracts")
    func fixedProcedureContracts() {
        expectRecordFailure(
            .unsupportedSchemaVersion(2),
            data: recordData(schemaVersion: 2)
        )
        expectRecordFailure(
            .unsupportedExperimentRecipeID("ES80-ELECTRICAL-CORRELATION-v1"),
            data: recordData(experimentRecipeID: "ES80-ELECTRICAL-CORRELATION-v1")
        )
        expectRecordFailure(
            .invalidProcedureVersion,
            data: recordData(procedureVersion: "V13")
        )
    }

    @Test("trusted digest is canonical exact SHA-256, never normalized from loose text")
    func digestShapeFailsClosed() {
        expectRecordFailure(
            .invalidExecutableSHA256,
            data: recordData(executableSHA256: abcSHA256.uppercased())
        )
        expectRecordFailure(
            .invalidExecutableSHA256,
            data: recordData(executableSHA256: String(abcSHA256.dropLast()))
        )
    }

    @Test("build label mismatch cannot reuse an otherwise matching trusted record")
    func buildIdentifierMismatch() throws {
        let record = try decodeRecord()
        let runtime = try makeRuntime(
            buildIdentifier: "Capture Build V14-F2",
            sourceCommit: sourceCommit,
            executableBytes: Data("abc".utf8)
        )

        expectPreflightFailure(
            .buildIdentifierMismatch,
            runtime: runtime,
            record: record
        )
    }

    @Test("source commit mismatch cannot reuse an otherwise matching trusted record")
    func sourceCommitMismatch() throws {
        let record = try decodeRecord()
        let runtime = try makeRuntime(
            buildIdentifier: buildIdentifier,
            sourceCommit: "1123456789abcdef0123456789abcdef01234567",
            executableBytes: Data("abc".utf8)
        )

        expectPreflightFailure(
            .sourceCommitSHAMismatch,
            runtime: runtime,
            record: record
        )
    }

    @Test("different running executable bytes fail exact build binding")
    func executableMismatch() throws {
        let record = try decodeRecord()
        let runtime = try makeRuntime(
            buildIdentifier: buildIdentifier,
            sourceCommit: sourceCommit,
            executableBytes: Data("different executable".utf8)
        )

        expectPreflightFailure(
            .executableSHA256Mismatch,
            runtime: runtime,
            record: record
        )
    }

    @Test("record build identifiers and procedure versions reject padded or control text")
    func textualIdentifiersFailClosed() {
        expectRecordFailure(
            .invalidBuildIdentifier,
            data: recordData(buildIdentifier: " \(buildIdentifier)")
        )
        expectRecordFailure(
            .invalidProcedureVersion,
            data: recordData(procedureVersion: "V14\n")
        )
    }

    private func decodeRecord() throws -> PassiveBluetoothCaptureTrustedBuildRecord {
        try RecordReader.decodeTrustedRecord(recordData())
    }

    private func recordData(
        schemaVersion: Int = 1,
        buildIdentifier: String? = nil,
        sourceCommitSHA: String? = nil,
        executableSHA256: String? = nil,
        experimentRecipeID: String = "ES80-FINGERPRINT-v1",
        procedureVersion: String = "V14"
    ) -> Data {
        let object: [String: Any] = [
            "schemaVersion": schemaVersion,
            "buildIdentifier": buildIdentifier ?? self.buildIdentifier,
            "sourceCommitSHA": sourceCommitSHA ?? sourceCommit,
            "executableSHA256": executableSHA256 ?? abcSHA256,
            "experimentRecipeID": experimentRecipeID,
            "procedureVersion": procedureVersion,
        ]
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func makeRuntime(
        buildIdentifier: String,
        sourceCommit: String,
        executableBytes: Data
    ) throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey: sourceCommit,
            ],
            executableData: executableBytes
        )
    }

    private func expectRecordFailure(
        _ expected: RecordError,
        data: Data,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            _ = try RecordReader.decodeTrustedRecord(data)
            Issue.record("expected trusted build record failure: \(expected)", sourceLocation: sourceLocation)
        } catch let error as RecordError {
            #expect(error == expected, sourceLocation: sourceLocation)
        } catch {
            Issue.record("unexpected error: \(error)", sourceLocation: sourceLocation)
        }
    }

    private func expectPreflightFailure(
        _ expected: PreflightError,
        runtime: PassiveBluetoothCaptureRuntimeBuildIdentity,
        record: PassiveBluetoothCaptureTrustedBuildRecord,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            _ = try PassiveBluetoothCaptureBuildPreflight.evaluate(
                runtimeIdentity: runtime,
                trustedRecord: record
            )
            Issue.record("expected build preflight failure: \(expected)", sourceLocation: sourceLocation)
        } catch let error as PreflightError {
            #expect(error == expected, sourceLocation: sourceLocation)
        } catch {
            Issue.record("unexpected error: \(error)", sourceLocation: sourceLocation)
        }
    }
}
