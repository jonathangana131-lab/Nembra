import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth transport fingerprint")
struct PassiveBluetoothTransportFingerprintTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("FD50 advertisement alone is only a service-level candidate when explicitly scoped")
    func fd50ServiceOnly() throws {
        var session = try makeSession()
        try session.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: "test",
                serviceUUIDs: ["fd50"]
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )

        let report = try #require(PassiveBluetoothTransportFingerprint.analyze(session, peripheralIdentifier: "test"))
        #expect(report.peripheralIdentifier == "test")
        #expect(report.observedServiceUUIDs == ["FD50"])
        #expect(report.candidateMatches.count == 1)
        #expect(report.candidateMatches[0].family == .tuyaModernFD50)
        #expect(report.candidateMatches[0].strength == .serviceObserved)
        #expect(report.candidateMatches[0].observedCharacteristicUUIDs.isEmpty)
    }

    @Test("unscoped advertisement-only capture refuses to guess a target peripheral")
    func advertisementOnlyUnscopedFailsClosed() throws {
        var session = try makeSession()
        try session.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: "nearby-tuya-device",
                serviceUUIDs: ["FD50"]
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )

        let report = PassiveBluetoothTransportFingerprint.analyze(session)
        #expect(report.peripheralIdentifier.isEmpty)
        #expect(report.observedServiceUUIDs.isEmpty)
        #expect(report.candidateMatches.isEmpty)
    }

    @Test("unscoped analysis uses the sole peripheral with GATT evidence and ignores nearby advertisements")
    func soleGattPeripheralWinsConservatively() throws {
        var session = try makeSession()
        try session.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: "nearby-tuya-device",
                serviceUUIDs: ["FD50"]
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )
        try session.append(
            .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: "selected-es80",
                serviceUUID: "A201",
                isPrimary: true
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: .now
        )

        let report = PassiveBluetoothTransportFingerprint.analyze(session)
        #expect(report.peripheralIdentifier == "selected-es80")
        #expect(report.observedServiceUUIDs == ["A201"])
        #expect(report.candidateMatches.map(\.family) == [.tuyaLegacyA201])
    }

    @Test("A201 plus 2B10 and 2B11 is a strong candidate but not a protocol verdict")
    func a201DataPath() throws {
        var session = try makeSession()
        try appendService("A201", sequence: 1, to: &session)
        try appendCharacteristic("2b10", service: "a201", sequence: 2, to: &session)
        try appendCharacteristic("2B11", service: "A201", sequence: 3, to: &session)

        let report = try #require(PassiveBluetoothTransportFingerprint.analyze(session, peripheralIdentifier: "test"))
        let match = try #require(report.candidateMatches.first)
        #expect(match.family == .tuyaLegacyA201)
        #expect(match.strength == .expectedDataPathObserved)
        #expect(match.observedCharacteristicUUIDs == ["2B10", "2B11"])
    }

    @Test("candidate strength never combines GATT topology across continuity generations")
    func continuityGenerationsDoNotCombineCandidateStrength() throws {
        var session = try makeSession()
        try appendService("A201", sequence: 1, to: &session)
        try appendCharacteristic("2B10", service: "A201", sequence: 2, to: &session)
        try session.append(
            .interruption(try PassiveBluetoothCaptureInterruption(reason: "GATT services invalidated")),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3,
            receivedAtDate: .now
        )
        try appendService("A201", sequence: 4, to: &session)
        try appendCharacteristic("2B11", service: "A201", sequence: 5, to: &session)

        let report = try #require(PassiveBluetoothTransportFingerprint.analyze(session, peripheralIdentifier: "test"))
        #expect(report.characteristicUUIDsByService["A201"] == ["2B10", "2B11"])
        let match = try #require(report.candidateMatches.first)
        #expect(match.family == .tuyaLegacyA201)
        #expect(match.strength == .characteristicFamilyObserved)
        #expect(match.observedCharacteristicUUIDs != ["2B10", "2B11"])
    }

    @Test("strongest candidate strength may come from one later continuity generation")
    func strongestSingleContinuityGenerationWins() throws {
        var session = try makeSession()
        try appendService("A201", sequence: 1, to: &session)
        try session.append(
            .interruption(try PassiveBluetoothCaptureInterruption(reason: "GATT services invalidated")),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: .now
        )
        try appendService("A201", sequence: 3, to: &session)
        try appendCharacteristic("2B10", service: "A201", sequence: 4, to: &session)
        try appendCharacteristic("2B11", service: "A201", sequence: 5, to: &session)

        let report = try #require(PassiveBluetoothTransportFingerprint.analyze(session, peripheralIdentifier: "test"))
        let match = try #require(report.candidateMatches.first)
        #expect(match.family == .tuyaLegacyA201)
        #expect(match.strength == .expectedDataPathObserved)
        #expect(match.observedCharacteristicUUIDs == ["2B10", "2B11"])
    }

    @Test("multiple family fingerprints remain multiple instead of forcing a winner")
    func multipleCandidates() throws {
        var session = try makeSession()
        try appendService("A201", sequence: 1, to: &session)
        try appendCharacteristic("2B10", service: "A201", sequence: 2, to: &session)
        try appendService("1910", sequence: 3, to: &session)
        try appendCharacteristic("2B10", service: "1910", sequence: 4, to: &session)
        try appendCharacteristic("2B11", service: "1910", sequence: 5, to: &session)

        let report = try #require(PassiveBluetoothTransportFingerprint.analyze(session, peripheralIdentifier: "test"))
        #expect(report.candidateMatches.map(\.family) == [.tuyaLegacy1910, .tuyaLegacyA201])
        #expect(report.candidateMatches.map(\.strength) == [.expectedDataPathObserved, .characteristicFamilyObserved])
    }

    @Test("unknown GATT evidence remains valid with no candidate match")
    func unknownFamily() throws {
        var session = try makeSession()
        try appendService("FFF0", sequence: 1, to: &session)
        try appendCharacteristic("FFF1", service: "FFF0", sequence: 2, to: &session)

        let report = try #require(PassiveBluetoothTransportFingerprint.analyze(session, peripheralIdentifier: "test"))
        #expect(report.observedServiceUUIDs == ["FFF0"])
        #expect(report.characteristicUUIDsByService["FFF0"] == ["FFF1"])
        #expect(report.candidateMatches.isEmpty)
    }

    @Test("absent explicit target is distinct from an observed unknown transport")
    func absentExplicitTargetFailsClosed() throws {
        var session = try makeSession()
        try appendService("FFF0", sequence: 1, to: &session)
        try appendCharacteristic("FFF1", service: "FFF0", sequence: 2, to: &session)

        #expect(PassiveBluetoothTransportFingerprint.analyze(
            session,
            peripheralIdentifier: "missing-target"
        ) == nil)

        let observed = try #require(PassiveBluetoothTransportFingerprint.analyze(
            session,
            peripheralIdentifier: "test"
        ))
        #expect(observed.observedServiceUUIDs == ["FFF0"])
        #expect(observed.candidateMatches.isEmpty)
    }

    @Test("value-only partial capture can still report observed GATT identifiers")
    func valueOnlyPartialCapture() throws {
        var session = try makeSession()
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: "test",
                serviceUUID: "FD50",
                characteristicUUID: "00000002-0000-1001-8001-00805F9B07D0",
                origin: .subscriptionUpdate,
                payload: Data([0x01, 0x02])
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )

        let report = try #require(PassiveBluetoothTransportFingerprint.analyze(session, peripheralIdentifier: "test"))
        #expect(report.candidateMatches.count == 1)
        #expect(report.candidateMatches[0].family == .tuyaModernFD50)
        #expect(report.candidateMatches[0].strength == .characteristicFamilyObserved)
    }

    @Test("nearby unrelated Tuya advertisement cannot contaminate selected peripheral fingerprint")
    func unrelatedPeripheralIsolation() throws {
        var session = try makeSession()
        try session.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: "nearby-tuya-device",
                serviceUUIDs: ["FD50"]
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )
        try session.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: "selected-es80",
                serviceUUIDs: ["A201"]
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: .now
        )

        let selected = try #require(PassiveBluetoothTransportFingerprint.analyze(
            session,
            peripheralIdentifier: "selected-es80"
        ))
        #expect(selected.observedServiceUUIDs == ["A201"])
        #expect(selected.candidateMatches.map(\.family) == [.tuyaLegacyA201])

        let reports = PassiveBluetoothTransportFingerprint.analyzeAll(session)
        #expect(reports.map(\.peripheralIdentifier) == ["nearby-tuya-device", "selected-es80"])
        #expect(reports[0].candidateMatches.map(\.family) == [.tuyaModernFD50])
        #expect(reports[1].candidateMatches.map(\.family) == [.tuyaLegacyA201])
    }

    private func makeSession() throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
    }

    private func appendService(
        _ uuid: String,
        sequence: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: "test",
                serviceUUID: uuid,
                isPrimary: true
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: sequence,
            receivedAtDate: .now
        )
    }

    private func appendCharacteristic(
        _ uuid: String,
        service: String,
        sequence: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .characteristic(try PassiveBluetoothCharacteristicObservation(
                peripheralIdentifier: "test",
                serviceUUID: service,
                characteristicUUID: uuid,
                properties: [.read]
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: sequence,
            receivedAtDate: .now
        )
    }
}
