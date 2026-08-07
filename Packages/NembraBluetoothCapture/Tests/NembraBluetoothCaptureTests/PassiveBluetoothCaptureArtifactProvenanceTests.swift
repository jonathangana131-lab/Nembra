import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth capture artifact provenance")
struct PassiveBluetoothCaptureArtifactProvenanceTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )
    private let revision = "ae0f2a20a6aecec02d972b9a66f75864d97796e9"
    private let target = "11111111-2222-3333-4444-555555555555"

    @Test("SHA-256 helper uses the standard lowercase artifact digest")
    func sha256DigestIsStandard() {
        let digest = PassiveBluetoothCaptureArtifactProvenanceBuilder.sha256Hex(
            of: Data("abc".utf8)
        )

        #expect(
            digest
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("sidecar binds exact bytes plus session and operator provenance")
    func sidecarBindsExactCaptureBytes() throws {
        let session = try makeSessionWithConnection()
        let prettyJSON = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: true)
        let compactJSON = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_500)

        let sidecar = try makeSidecar(
            captureJSON: prettyJSON,
            createdAt: createdAt
        )

        #expect(sidecar.schemaVersion == 1)
        #expect(sidecar.sourceArtifact.byteCount == prettyJSON.count)
        #expect(sidecar.sourceArtifact.captureSchemaVersion == 2)
        #expect(sidecar.sourceArtifact.sessionID == session.id)
        #expect(sidecar.sourceArtifact.sessionStartedAt == session.startedAt)
        #expect(sidecar.nembraBuild.sourceRevision == revision)
        #expect(sidecar.nembraBuild.appVersion == "1.0")
        #expect(sidecar.nembraBuild.appBuild == "42")
        #expect(sidecar.selectedTarget.peripheralIdentifier == target)
        #expect(sidecar.selectedTarget.physicalCorrelationNote == "rear wheel raised; target power-cycle correlated")
        #expect(sidecar.researchSetup.physicalStateNote == "stationary, charger disconnected, 73% visible in stock app")
        #expect(sidecar.researchSetup.acquisitionFailureNote == nil)
        #expect(sidecar.createdAt == createdAt)
        #expect(try sidecar.matchesSourceArtifact(prettyJSON))
        #expect(!(try sidecar.matchesSourceArtifact(compactJSON)))
    }

    @Test("semantically equal capture encodings remain distinct immutable artifacts")
    func formattingChangesArtifactDigest() throws {
        let session = try makeSessionWithConnection()
        let prettyJSON = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: true)
        let compactJSON = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)

        let prettySidecar = try makeSidecar(captureJSON: prettyJSON)
        let compactSidecar = try makeSidecar(captureJSON: compactJSON)

        #expect(prettyJSON != compactJSON)
        #expect(prettySidecar.sourceArtifact.sessionID == compactSidecar.sourceArtifact.sessionID)
        #expect(prettySidecar.sourceArtifact.sha256 != compactSidecar.sourceArtifact.sha256)
        #expect(try compactSidecar.matchesSourceArtifact(compactJSON))
        #expect(!(try compactSidecar.matchesSourceArtifact(prettyJSON)))
    }

    @Test("advertisement-only candidate cannot become selected-target provenance")
    func advertisementOnlyTargetFailsClosed() throws {
        var session = try makeSession()
        try session.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: target,
                localName: "ES80"
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1_000,
            receivedAtDate: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let captureJSON = try PassiveBluetoothCaptureJSON.encode(session)

        #expect(throws: PassiveBluetoothCaptureArtifactProvenanceError
            .selectedPeripheralNotAttributable(requested: target, available: [])) {
            try makeSidecar(captureJSON: captureJSON)
        }
    }

    @Test("selected target matching is exact and exposes available attributable identities")
    func targetIdentityIsOpaqueAndExact() throws {
        let session = try makeSessionWithConnection()
        let captureJSON = try PassiveBluetoothCaptureJSON.encode(session)

        #expect(throws: PassiveBluetoothCaptureArtifactProvenanceError
            .selectedPeripheralNotAttributable(requested: "\(target.lowercased())", available: [target])) {
            try PassiveBluetoothCaptureArtifactProvenanceBuilder.make(
                captureJSON: captureJSON,
                nembraSourceRevision: revision,
                selectedPeripheralIdentifier: target.lowercased(),
                physicalCorrelationNote: "physical power-cycle correlation",
                researchSetupNote: "stationary, charger disconnected"
            )
        }
    }

    @Test("blank or padded target identifiers are rejected before attribution")
    func invalidTargetIdentifierFailsClosed() throws {
        let captureJSON = try PassiveBluetoothCaptureJSON.encode(makeSessionWithConnection())

        #expect(throws: PassiveBluetoothCaptureArtifactProvenanceError.emptySelectedPeripheralIdentifier) {
            try PassiveBluetoothCaptureArtifactProvenanceBuilder.make(
                captureJSON: captureJSON,
                nembraSourceRevision: revision,
                selectedPeripheralIdentifier: "  \(target) ",
                physicalCorrelationNote: "physical power-cycle correlation",
                researchSetupNote: "stationary, charger disconnected"
            )
        }
    }

    @Test("branch names and abbreviated SHAs cannot masquerade as exact build revision")
    func exactSourceRevisionIsRequired() throws {
        let captureJSON = try PassiveBluetoothCaptureJSON.encode(makeSessionWithConnection())

        for invalidRevision in ["main", "ae0f2a20", String(repeating: "A", count: 40)] {
            #expect(throws: PassiveBluetoothCaptureArtifactProvenanceError.invalidNembraSourceRevision) {
                try PassiveBluetoothCaptureArtifactProvenanceBuilder.make(
                    captureJSON: captureJSON,
                    nembraSourceRevision: invalidRevision,
                    selectedPeripheralIdentifier: target,
                    physicalCorrelationNote: "physical power-cycle correlation",
                    researchSetupNote: "stationary, charger disconnected"
                )
            }
        }
    }

    @Test("required physical-correlation and setup notes cannot be blank")
    func requiredOperatorNotesCannotBeBlank() throws {
        let captureJSON = try PassiveBluetoothCaptureJSON.encode(makeSessionWithConnection())

        #expect(throws: PassiveBluetoothCaptureArtifactProvenanceError.emptyPhysicalCorrelationNote) {
            try PassiveBluetoothCaptureArtifactProvenanceBuilder.make(
                captureJSON: captureJSON,
                nembraSourceRevision: revision,
                selectedPeripheralIdentifier: target,
                physicalCorrelationNote: "   ",
                researchSetupNote: "stationary"
            )
        }
        #expect(throws: PassiveBluetoothCaptureArtifactProvenanceError.emptyResearchSetupNote) {
            try PassiveBluetoothCaptureArtifactProvenanceBuilder.make(
                captureJSON: captureJSON,
                nembraSourceRevision: revision,
                selectedPeripheralIdentifier: target,
                physicalCorrelationNote: "power-cycle correlated",
                researchSetupNote: "\n\t"
            )
        }
    }

    @Test("optional build and acquisition-failure fields reject blank pseudo-provenance")
    func optionalMetadataMustBeMeaningfulWhenPresent() throws {
        let captureJSON = try PassiveBluetoothCaptureJSON.encode(makeSessionWithConnection())

        #expect(throws: PassiveBluetoothCaptureArtifactProvenanceError.emptyAppVersion) {
            try PassiveBluetoothCaptureArtifactProvenanceBuilder.make(
                captureJSON: captureJSON,
                nembraSourceRevision: revision,
                appVersion: " ",
                selectedPeripheralIdentifier: target,
                physicalCorrelationNote: "power-cycle correlated",
                researchSetupNote: "stationary"
            )
        }
        #expect(throws: PassiveBluetoothCaptureArtifactProvenanceError.emptyAppBuild) {
            try PassiveBluetoothCaptureArtifactProvenanceBuilder.make(
                captureJSON: captureJSON,
                nembraSourceRevision: revision,
                appBuild: "\n",
                selectedPeripheralIdentifier: target,
                physicalCorrelationNote: "power-cycle correlated",
                researchSetupNote: "stationary"
            )
        }
        #expect(throws: PassiveBluetoothCaptureArtifactProvenanceError.emptyAcquisitionFailureNote) {
            try PassiveBluetoothCaptureArtifactProvenanceBuilder.make(
                captureJSON: captureJSON,
                nembraSourceRevision: revision,
                selectedPeripheralIdentifier: target,
                physicalCorrelationNote: "power-cycle correlated",
                researchSetupNote: "stationary",
                acquisitionFailureNote: "\t"
            )
        }
    }

    @Test("versioned sidecar JSON round-trips through validation gates")
    func sidecarJSONRoundTrip() throws {
        let captureJSON = try PassiveBluetoothCaptureJSON.encode(makeSessionWithConnection())
        let original = try makeSidecar(
            captureJSON: captureJSON,
            acquisitionFailureNote: "discarded after acquisition entered fail-closed state",
            createdAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        let json = try original.jsonData()
        let decoded = try PassiveBluetoothCaptureArtifactProvenance.decodeJSON(json)

        #expect(decoded == original)
        #expect(try decoded.matchesSourceArtifact(captureJSON))
    }

    @Test("unsupported sidecar schema fails closed on import")
    func unsupportedSidecarSchemaFailsClosed() throws {
        let captureJSON = try PassiveBluetoothCaptureJSON.encode(makeSessionWithConnection())
        let sidecar = try makeSidecar(captureJSON: captureJSON)
        let json = try sidecar.jsonData(prettyPrinted: false)
        var object = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        object["schemaVersion"] = 99
        let unsupported = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: PassiveBluetoothCaptureArtifactProvenanceError.unsupportedSchemaVersion(99)) {
            try PassiveBluetoothCaptureArtifactProvenance.decodeJSON(unsupported)
        }
    }

    private func makeSession() throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeSessionWithConnection() throws -> PassiveBluetoothCaptureSession {
        var session = try makeSession()
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: target,
                state: .connected
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1_000,
            receivedAtDate: Date(timeIntervalSince1970: 1_700_000_001)
        )
        return session
    }

    private func makeSidecar(
        captureJSON: Data,
        acquisitionFailureNote: String? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_500)
    ) throws -> PassiveBluetoothCaptureArtifactProvenance {
        try PassiveBluetoothCaptureArtifactProvenanceBuilder.make(
            captureJSON: captureJSON,
            nembraSourceRevision: revision,
            appVersion: "1.0",
            appBuild: "42",
            selectedPeripheralIdentifier: target,
            physicalCorrelationNote: "rear wheel raised; target power-cycle correlated",
            researchSetupNote: "stationary, charger disconnected, 73% visible in stock app",
            acquisitionFailureNote: acquisitionFailureNote,
            createdAt: createdAt
        )
    }
}
