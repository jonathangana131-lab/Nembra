from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


source_path = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothCaptureFieldAuthorization.swift")
source = source_path.read_text()

replacements = [
    (
        "public let externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord\n    public let authorizationPayloadSHA256: String",
        "public let externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord\n    public let signedFieldArtifactEvidence: PassiveBluetoothCaptureSignedFieldArtifactEvidence\n    public let authorizationPayloadSHA256: String",
        "authorization result fields",
    ),
    (
        "externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord,\n        authorizationPayloadSHA256: String\n    ) {\n        self.externalBuildRecord = externalBuildRecord\n        self.authorizationPayloadSHA256 = authorizationPayloadSHA256",
        "externalBuildRecord: PassiveBluetoothCaptureExternalBuildRecord,\n        signedFieldArtifactEvidence: PassiveBluetoothCaptureSignedFieldArtifactEvidence,\n        authorizationPayloadSHA256: String\n    ) {\n        self.externalBuildRecord = externalBuildRecord\n        self.signedFieldArtifactEvidence = signedFieldArtifactEvidence\n        self.authorizationPayloadSHA256 = authorizationPayloadSHA256",
        "authorization result initializer",
    ),
    (
        "case invalidExternalBuildRecordBase64\n    case invalidAuthorizationPayloadBase64",
        "case invalidExternalBuildRecordBase64\n    case invalidSignedFieldArtifactEvidenceBase64\n    case invalidAuthorizationPayloadBase64",
        "evidence base64 error",
    ),
    (
        "case invalidExternalBuildRecordSHA256\n    case externalBuildRecordDigestMismatch\n    case invalidExternalBuildRecord",
        "case invalidExternalBuildRecordSHA256\n    case invalidSignedFieldArtifactEvidenceSHA256\n    case externalBuildRecordDigestMismatch\n    case signedFieldArtifactEvidenceDigestMismatch\n    case invalidExternalBuildRecord\n    case invalidSignedFieldArtifactEvidence\n    case signedFieldArtifactEvidenceBindingMismatch",
        "evidence digest errors",
    ),
    (
        "/// and schema-v3 external record are known and independently accepted.",
        "/// schema-v3 external record, and exact signed-field IPA evidence are known and independently accepted.",
        "verifier documentation",
    ),
    (
        "public static let envelopeSchemaVersion = 1\n    public static let authorizationPayloadSchemaVersion = 1",
        "public static let envelopeSchemaVersion = 2\n    public static let authorizationPayloadSchemaVersion = 2",
        "authorization schema versions",
    ),
    (
        "let schemaVersion: Int\n        let externalBuildRecordBase64: String\n        let authorizationPayloadBase64: String",
        "let schemaVersion: Int\n        let externalBuildRecordBase64: String\n        let signedFieldArtifactEvidenceBase64: String\n        let authorizationPayloadBase64: String",
        "envelope wire evidence",
    ),
    (
        "let decision: String\n        let externalBuildRecordSHA256: String",
        "let decision: String\n        let externalBuildRecordSHA256: String\n        let signedFieldArtifactEvidenceSHA256: String",
        "payload wire evidence",
    ),
    (
        "guard let authorizationPayloadData = decodeCanonicalBase64(\n            envelope.authorizationPayloadBase64\n        ) else {\n            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidAuthorizationPayloadBase64\n        }",
        "guard let signedFieldArtifactEvidenceData = decodeCanonicalBase64(\n            envelope.signedFieldArtifactEvidenceBase64\n        ) else {\n            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidSignedFieldArtifactEvidenceBase64\n        }\n        guard let authorizationPayloadData = decodeCanonicalBase64(\n            envelope.authorizationPayloadBase64\n        ) else {\n            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidAuthorizationPayloadBase64\n        }",
        "decode evidence base64",
    ),
    (
        "guard isCanonicalSHA256(payload.externalBuildRecordSHA256) else {\n            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidExternalBuildRecordSHA256\n        }",
        "guard isCanonicalSHA256(payload.externalBuildRecordSHA256) else {\n            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidExternalBuildRecordSHA256\n        }\n        guard isCanonicalSHA256(payload.signedFieldArtifactEvidenceSHA256) else {\n            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidSignedFieldArtifactEvidenceSHA256\n        }",
        "validate evidence digest",
    ),
    (
        "guard exactExternalRecordSHA256 == payload.externalBuildRecordSHA256 else {\n            throw PassiveBluetoothCaptureFieldAuthorizationError.externalBuildRecordDigestMismatch\n        }",
        "guard exactExternalRecordSHA256 == payload.externalBuildRecordSHA256 else {\n            throw PassiveBluetoothCaptureFieldAuthorizationError.externalBuildRecordDigestMismatch\n        }\n        let exactSignedFieldEvidenceSHA256 = sha256Hex(signedFieldArtifactEvidenceData)\n        guard exactSignedFieldEvidenceSHA256 == payload.signedFieldArtifactEvidenceSHA256 else {\n            throw PassiveBluetoothCaptureFieldAuthorizationError.signedFieldArtifactEvidenceDigestMismatch\n        }",
        "bind exact evidence digest",
    ),
    (
        "guard externalBuildRecord.infoPlistSHA256 == runtimeBuildIdentity.infoPlistSHA256 else {\n            throw PassiveBluetoothCaptureFieldAuthorizationError.runtimeInfoPlistMismatch\n        }\n\n        return PassiveBluetoothCaptureVerifiedFieldAuthorization(\n            externalBuildRecord: externalBuildRecord,\n            authorizationPayloadSHA256: sha256Hex(authorizationPayloadData)\n        )",
        "guard externalBuildRecord.infoPlistSHA256 == runtimeBuildIdentity.infoPlistSHA256 else {\n            throw PassiveBluetoothCaptureFieldAuthorizationError.runtimeInfoPlistMismatch\n        }\n\n        let signedFieldArtifactEvidence: PassiveBluetoothCaptureSignedFieldArtifactEvidence\n        do {\n            signedFieldArtifactEvidence = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON\n                .decodeDeclaration(signedFieldArtifactEvidenceData)\n        } catch {\n            throw PassiveBluetoothCaptureFieldAuthorizationError.invalidSignedFieldArtifactEvidence\n        }\n        do {\n            _ = try signedFieldArtifactEvidence.makeMechanicallyBoundSoftwareExportReference(\n                matching: externalBuildRecord,\n                running: runtimeBuildIdentity\n            )\n        } catch {\n            throw PassiveBluetoothCaptureFieldAuthorizationError.signedFieldArtifactEvidenceBindingMismatch\n        }\n\n        return PassiveBluetoothCaptureVerifiedFieldAuthorization(\n            externalBuildRecord: externalBuildRecord,\n            signedFieldArtifactEvidence: signedFieldArtifactEvidence,\n            authorizationPayloadSHA256: sha256Hex(authorizationPayloadData)\n        )",
        "parse and bind signed field evidence",
    ),
    (
        '"schemaVersion",\n            "externalBuildRecordBase64",\n            "authorizationPayloadBase64",',
        '"schemaVersion",\n            "externalBuildRecordBase64",\n            "signedFieldArtifactEvidenceBase64",\n            "authorizationPayloadBase64",',
        "closed-world envelope keys",
    ),
    (
        '"schemaVersion",\n            "decision",\n            "externalBuildRecordSHA256",',
        '"schemaVersion",\n            "decision",\n            "externalBuildRecordSHA256",\n            "signedFieldArtifactEvidenceSHA256",',
        "closed-world payload keys",
    ),
]

for old, new, label in replacements:
    source = replace_once(source, old, new, label)
source_path.write_text(source)


test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/PassiveBluetoothCaptureFieldAuthorizationTests.swift")
tests = test_path.read_text()

tests = replace_once(
    tests,
    "#expect(authorization.externalBuildRecord.procedureVersion == \"V14\")\n        #expect(authorization.authorizationPayloadSHA256 == sha256Hex(fixture.payload))",
    "#expect(authorization.externalBuildRecord.procedureVersion == \"V14\")\n        #expect(authorization.signedFieldArtifactEvidence.exactEvidenceRecordSHA256 == sha256Hex(fixture.fieldEvidence))\n        #expect(authorization.signedFieldArtifactEvidence.ipaSHA256 == String(repeating: \"a\", count: 64))\n        #expect(authorization.authorizationPayloadSHA256 == sha256Hex(fixture.payload))",
    "valid authorization evidence assertions",
)

tests = replace_once(
    tests,
    '''        let payload = try json([\n            "schemaVersion": 1,\n            "decision": "NO_GO",\n            "externalBuildRecordSHA256": sha256Hex(record),\n        ])\n        let envelope = try makeEnvelope(record: record, payload: payload, signingKey: signingKey)''',
    '''        let fieldEvidence = try makeFieldEvidence(record: record)\n        let payload = try json([\n            "schemaVersion": 2,\n            "decision": "NO_GO",\n            "externalBuildRecordSHA256": sha256Hex(record),\n            "signedFieldArtifactEvidenceSHA256": sha256Hex(fieldEvidence),\n        ])\n        let envelope = try makeEnvelope(\n            record: record,\n            fieldEvidence: fieldEvidence,\n            payload: payload,\n            signingKey: signingKey\n        )''',
    "NO_GO fixture schema v2",
)

new_test_anchor = '''    @Test\n    func signedMalformedExternalBuildRecordCannotMintAuthority() throws {'''
new_test = '''    @Test\n    func signedGoCannotBeReboundToDifferentSignedIPAEvidenceBytes() throws {\n        let fixture = try makeFixture()\n        var alternateObject = try jsonObject(fixture.fieldEvidence)\n        alternateObject["ipaSHA256"] = String(repeating: "b", count: 64)\n        let alternateEvidence = try json(alternateObject)\n        let rebound = try makeEnvelope(\n            record: fixture.record,\n            fieldEvidence: alternateEvidence,\n            payload: fixture.payload,\n            signingKey: fixture.privateKey\n        )\n\n        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.signedFieldArtifactEvidenceDigestMismatch) {\n            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(\n                rebound,\n                publicKeyX963Representation: fixture.privateKey.publicKey.x963Representation,\n                runtimeBuildIdentity: fixture.runtimeIdentity\n            )\n        }\n    }\n\n    @Test\n    func signedFieldEvidenceMustMatchAcceptedExternalAndRunningBuild() throws {\n        let signingKey = P256.Signing.PrivateKey()\n        let runtimeIdentity = try makeRuntimeIdentity()\n        let record = try json(baseRecordObject())\n        var detachedObject = try jsonObject(try makeFieldEvidence(record: record))\n        detachedObject["infoPlistSHA256"] = String(repeating: "d", count: 64)\n        let detachedEvidence = try json(detachedObject)\n        let payload = try makePayload(record: record, fieldEvidence: detachedEvidence)\n        let envelope = try makeEnvelope(\n            record: record,\n            fieldEvidence: detachedEvidence,\n            payload: payload,\n            signingKey: signingKey\n        )\n\n        #expect(throws: PassiveBluetoothCaptureFieldAuthorizationError.signedFieldArtifactEvidenceBindingMismatch) {\n            _ = try PassiveBluetoothCaptureFieldAuthorizationVerifier.verify(\n                envelope,\n                publicKeyX963Representation: signingKey.publicKey.x963Representation,\n                runtimeBuildIdentity: runtimeIdentity\n            )\n        }\n    }\n\n    @Test\n    func signedMalformedExternalBuildRecordCannotMintAuthority() throws {'''
tests = replace_once(tests, new_test_anchor, new_test, "signed field evidence adversarial tests")

tests = replace_once(
    tests,
    '''        let record: Data\n        let payload: Data\n        let envelope: Data''',
    '''        let record: Data\n        let fieldEvidence: Data\n        let payload: Data\n        let envelope: Data''',
    "fixture evidence field",
)

tests = replace_once(
    tests,
    '''        let record = try json(baseRecordObject())\n        let payload = try makePayload(record: record)\n        let envelope = try makeEnvelope(record: record, payload: payload, signingKey: signingKey)\n        return Fixture(\n            privateKey: signingKey,\n            runtimeIdentity: runtimeIdentity,\n            record: record,\n            payload: payload,\n            envelope: envelope\n        )''',
    '''        let record = try json(baseRecordObject())\n        let fieldEvidence = try makeFieldEvidence(record: record)\n        let payload = try makePayload(record: record, fieldEvidence: fieldEvidence)\n        let envelope = try makeEnvelope(\n            record: record,\n            fieldEvidence: fieldEvidence,\n            payload: payload,\n            signingKey: signingKey\n        )\n        return Fixture(\n            privateKey: signingKey,\n            runtimeIdentity: runtimeIdentity,\n            record: record,\n            fieldEvidence: fieldEvidence,\n            payload: payload,\n            envelope: envelope\n        )''',
    "fixture construction",
)

tests = replace_once(
    tests,
    '''    private func makePayload(record: Data) throws -> Data {\n        try json([\n            "schemaVersion": 1,\n            "decision": "GO",\n            "externalBuildRecordSHA256": sha256Hex(record),\n        ])\n    }\n\n    private func makeEnvelope(\n        record: Data,\n        payload: Data,\n        signingKey: P256.Signing.PrivateKey\n    ) throws -> Data {\n        let signature = try signingKey.signature(for: payload)\n        return try json([\n            "schemaVersion": 1,\n            "externalBuildRecordBase64": record.base64EncodedString(),\n            "authorizationPayloadBase64": payload.base64EncodedString(),\n            "signatureDERBase64": signature.derRepresentation.base64EncodedString(),\n        ])\n    }''',
    '''    private func makeFieldEvidence(record: Data) throws -> Data {\n        try json([\n            "schemaVersion": 2,\n            "authority": "signed-field-artifact-evidence-not-field-authorization",\n            "buildIdentifier": buildIdentifier,\n            "buildInstanceID": buildInstanceID,\n            "sourceCommitSHA": sourceCommitSHA,\n            "bundleIdentifier": "com.jonathangana131.nembra",\n            "platformName": "iphoneos",\n            "supportedPlatforms": ["iPhoneOS"],\n            "teamIdentifier": "ABCDEFGHIJ",\n            "signingAuthorities": ["Apple Development: Nembra"],\n            "codeDirectoryHash": String(repeating: "c", count: 40),\n            "provisioningProfileUUID": "12345678-1234-4234-8234-123456789abc",\n            "provisioningProfileExpirationUTC": "2030-01-01T00:00:00Z",\n            "ipaSHA256": String(repeating: "a", count: 64),\n            "ipaByteCount": 123_456,\n            "executableSHA256": sha256Hex(executableData),\n            "infoPlistSHA256": sha256Hex(infoPlistData),\n            "externalBuildRecordSHA256": sha256Hex(record),\n            "experimentRecipeID": "ES80-FINGERPRINT-v1",\n            "procedureVersion": "V14",\n        ])\n    }\n\n    private func makePayload(record: Data, fieldEvidence: Data? = nil) throws -> Data {\n        let exactFieldEvidence = try fieldEvidence ?? makeFieldEvidence(record: record)\n        return try json([\n            "schemaVersion": 2,\n            "decision": "GO",\n            "externalBuildRecordSHA256": sha256Hex(record),\n            "signedFieldArtifactEvidenceSHA256": sha256Hex(exactFieldEvidence),\n        ])\n    }\n\n    private func makeEnvelope(\n        record: Data,\n        fieldEvidence: Data? = nil,\n        payload: Data,\n        signingKey: P256.Signing.PrivateKey\n    ) throws -> Data {\n        let exactFieldEvidence = try fieldEvidence ?? makeFieldEvidence(record: record)\n        let signature = try signingKey.signature(for: payload)\n        return try json([\n            "schemaVersion": 2,\n            "externalBuildRecordBase64": record.base64EncodedString(),\n            "signedFieldArtifactEvidenceBase64": exactFieldEvidence.base64EncodedString(),\n            "authorizationPayloadBase64": payload.base64EncodedString(),\n            "signatureDERBase64": signature.derRepresentation.base64EncodedString(),\n        ])\n    }''',
    "schema v2 test helpers",
)

test_path.write_text(tests)
