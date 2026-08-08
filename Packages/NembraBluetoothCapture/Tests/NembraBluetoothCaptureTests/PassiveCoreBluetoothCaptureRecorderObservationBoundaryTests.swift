import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth recorder observation boundaries")
struct PassiveCoreBluetoothCaptureRecorderObservationBoundaryTests {
    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    private static func recorderSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NembraBluetoothCapture package root
        let recorder = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("NembraBluetoothCapture")
            .appendingPathComponent("PassiveCoreBluetoothCaptureRecorder.swift")
        return try String(contentsOf: recorder, encoding: .utf8)
    }

    @Test("recorder atomically binds quiet boundaries to the accepted raw-record prefix")
    func recordsWatermarkedQuietInterval() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 6_000)
        )
        try await recorder.record(
            .interruption(try PassiveBluetoothCaptureInterruption(reason: "fixture")),
            receivedAtUptimeNanoseconds: 1_000,
            receivedAtDate: Date(timeIntervalSince1970: 6_001)
        )
        try await recorder.recordObservationBoundary(
            .finiteAcquisitionReady,
            observedAtUptimeNanoseconds: 2_000,
            observedAtDate: Date(timeIntervalSince1970: 6_002)
        )
        try await recorder.recordObservationBoundary(
            .observationHorizon,
            observedAtUptimeNanoseconds: 60_000_002_000,
            observedAtDate: Date(timeIntervalSince1970: 6_062)
        )

        let session = await recorder.snapshot()
        #expect(session.records.count == 1)
        #expect(session.observationBoundaries.count == 2)
        #expect(session.observationBoundaries[0].recordSequenceWatermark == 1)
        #expect(session.observationBoundaries[1].recordSequenceWatermark == 1)
        #expect(
            session.observationBoundaries[1].observedAtUptimeNanoseconds
                - session.observationBoundaries[0].observedAtUptimeNanoseconds
                == 60_000_000_000
        )

        let encoded = try await recorder.encodedJSON(prettyPrinted: false)
        let decoded = try PassiveBluetoothCaptureJSON.decode(encoded)
        #expect(decoded == session)
    }

    @Test("ready boundary watermark advances with later accepted callback evidence")
    func laterBoundaryUsesLaterRecordWatermark() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 6_100)
        )
        let gap = try PassiveBluetoothCaptureInterruption(reason: "fixture")

        try await recorder.record(
            .interruption(gap),
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 6_101)
        )
        try await recorder.recordObservationBoundary(
            .finiteAcquisitionReady,
            observedAtUptimeNanoseconds: 110,
            observedAtDate: Date(timeIntervalSince1970: 6_102)
        )
        try await recorder.record(
            .interruption(gap),
            receivedAtUptimeNanoseconds: 120,
            receivedAtDate: Date(timeIntervalSince1970: 6_103)
        )
        try await recorder.recordObservationBoundary(
            .finiteAcquisitionReady,
            observedAtUptimeNanoseconds: 130,
            observedAtDate: Date(timeIntervalSince1970: 6_104)
        )

        let session = await recorder.snapshot()
        #expect(session.records.map(\.sequenceNumber) == [1, 2])
        #expect(session.observationBoundaries.map(\.recordSequenceWatermark) == [1, 2])
    }

    @Test("terminal horizon prevents later raw or lifecycle evidence")
    func horizonIsTerminalAtRecorderBoundary() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 6_200)
        )
        try await recorder.recordObservationBoundary(
            .observationHorizon,
            observedAtUptimeNanoseconds: 100,
            observedAtDate: Date(timeIntervalSince1970: 6_201)
        )

        await #expect(throws: PassiveBluetoothCaptureValidationError.evidenceAfterObservationHorizon) {
            try await recorder.record(
                .interruption(try PassiveBluetoothCaptureInterruption(reason: "late")),
                receivedAtUptimeNanoseconds: 101,
                receivedAtDate: Date(timeIntervalSince1970: 6_202)
            )
        }
        await #expect(throws: PassiveBluetoothCaptureValidationError.evidenceAfterObservationHorizon) {
            try await recorder.recordObservationBoundary(
                .finiteAcquisitionReady,
                observedAtUptimeNanoseconds: 102,
                observedAtDate: Date(timeIntervalSince1970: 6_203)
            )
        }
    }

    @Test("only the clock-owning observation-boundary API is public")
    func explicitBoundaryClockIsPackageInternal() throws {
        let source = try Self.recorderSource()
        let publicBoundarySignature = "public func recordObservationBoundary("
        #expect(source.components(separatedBy: publicBoundarySignature).count - 1 == 1)

        let internalExplicitSignature = "func recordObservationBoundary(\n        _ kind: PassiveBluetoothObservationBoundaryKind,\n        observedAtUptimeNanoseconds: UInt64,"
        #expect(source.contains(internalExplicitSignature))
        #expect(!source.contains("public \(internalExplicitSignature)"))
    }
}
