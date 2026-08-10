import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted application evidence export seal")
struct TuyaAcceptedApplicationEvidenceSealSourceTests {
    @Test("successful package seal freezes app-exportable accepted evidence before another suspension point")
    func acceptanceSealFreezesExportPrefixSynchronously() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let seal = try section(
            in: String(watchdog),
            from: "try await sessionLedger.sealAcceptedObservation(for: token)",
            to: "} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed"
        )
        let body = String(seal)

        guard let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)"),
              let frozenPrefix = body.range(of: "sealedAcceptedEventPrefix =", range: packageSeal.upperBound..<body.endIndex) else {
            Issue.record("Successful package seal must synchronously snapshot the exportable accepted event prefix.")
            throw SourceContractError.sectionMissing
        }

        #expect(body[frozenPrefix.upperBound...].contains("events"))
        if let nextAwait = body.range(of: "await ", range: packageSeal.upperBound..<body.endIndex) {
            #expect(frozenPrefix.lowerBound < nextAwait.lowerBound)
        }
    }

    @Test("accepted export fails closed onto the frozen prefix instead of the mutable live event log")
    func acceptedExportUsesFrozenEventPrefix() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("private var sealedAcceptedEventPrefix: [Event]?"))

        let export = try section(
            in: app,
            from: "func prepareExport()",
            to: "private func resetDiscoverySessionOnly"
        )
        let body = String(export)

        #expect(body.contains("if phase == .accepted"))
        #expect(body.contains("guard let acceptedEventPrefix = self.sealedAcceptedEventPrefix"))
        #expect(body.contains("sealedAcceptedEventPrefix = acceptedEventPrefix"))
        #expect(body.contains("events: sealedAcceptedEventPrefix"))
        #expect(!body.contains("events: events\n"))
    }

    @Test("starting a fresh correlation life clears the prior accepted export prefix")
    func freshCorrelationClearsPriorAcceptedPrefix() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        )

        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
    }


    @Test("package-admitted structured values are copied before the callback suspends again")
    func acceptedApplicationValuesAreCopiedBeforeNextSuspension() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receive = try section(
            in: app,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        )
        let body = String(receive)

        guard let admission = body.range(of: "try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)"),
              let valueLog = body.range(of: "log(\"tuya_application_update\"", range: admission.upperBound..<body.endIndex),
              let nextAwait = body.range(of: "await ", range: admission.upperBound..<body.endIndex) else {
            Issue.record("Accepted application-value chronology anchors are missing.")
            throw SourceContractError.sectionMissing
        }

        #expect(valueLog.lowerBound < nextAwait.lowerBound)
    }

    @Test("canonical seal waits for current-generation structured evidence parity")
    func canonicalSealRequiresCurrentGenerationStructuredEvidenceParity() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let readyCase = body.range(of: "case .readyForStationaryMapping:"),
              let parity = body.range(of: "acceptedApplicationEventCount(for: token) == self.applicationUpdateCount", range: readyCase.upperBound..<body.endIndex),
              let seal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: readyCase.upperBound..<body.endIndex) else {
            Issue.record("Canonical seal must prove current-generation structured evidence parity first.")
            throw SourceContractError.sectionMissing
        }

        #expect(parity.lowerBound < seal.lowerBound)
        #expect(app.contains("$0.kind == \"tuya_application_update\" && $0.details[\"generation\"] == generation"))
    }


    @Test("canonical seal closes new application admission before awaiting package seal")
    func canonicalSealUsesMainActorAdmissionLatch() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receive = try section(
            in: app,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        )
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let receiveBody = String(receive)
        let watchdogBody = String(watchdog)

        guard let sealGuard = receiveBody.range(of: "guard !acceptanceSealInProgress else"),
              let increment = receiveBody.range(of: "applicationAdmissionInFlightCount += 1"),
              let record = receiveBody.range(of: "try await sessionLedger.recordApplicationUpdate", range: increment.upperBound..<receiveBody.endIndex) else {
            Issue.record("Application admission must be latched before package mutation.")
            throw SourceContractError.sectionMissing
        }
        #expect(sealGuard.lowerBound < increment.lowerBound)
        #expect(increment.lowerBound < record.lowerBound)
        #expect(receiveBody.contains("defer { applicationAdmissionInFlightCount -= 1 }"))

        guard let readyCase = watchdogBody.range(of: "case .readyForStationaryMapping:"),
              let inFlightFence = watchdogBody.range(of: "applicationAdmissionInFlightCount == 0", range: readyCase.upperBound..<watchdogBody.endIndex),
              let latch = watchdogBody.range(of: "acceptanceSealInProgress = true", range: inFlightFence.upperBound..<watchdogBody.endIndex),
              let packageSeal = watchdogBody.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: latch.upperBound..<watchdogBody.endIndex) else {
            Issue.record("Canonical seal must fence in-flight admission and close the latch before awaiting package seal.")
            throw SourceContractError.sectionMissing
        }
        #expect(inFlightFence.lowerBound < latch.lowerBound)
        #expect(latch.lowerBound < packageSeal.lowerBound)
    }

    @Test("fresh correlation life reopens application admission only after the prior life is retired")
    func freshCorrelationResetsSealLatch() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        )
        #expect(reset.contains("acceptanceSealInProgress = false"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
