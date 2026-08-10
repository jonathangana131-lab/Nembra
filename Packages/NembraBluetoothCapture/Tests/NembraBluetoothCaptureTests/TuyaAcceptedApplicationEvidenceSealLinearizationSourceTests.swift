import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted application evidence seal linearization")
struct TuyaAcceptedApplicationEvidenceSealLinearizationSourceTests {
    @Test("acceptance owns an explicit MainActor admission fence for application updates")
    func acceptanceHasApplicationAdmissionFence() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(
            in: app,
            from: "private final class SecureLinkController",
            to: "private protocol OfficialTuyaDriver"
        )
        let body = String(controller)

        #expect(body.contains("applicationUpdateMutationsInFlight"), Comment(rawValue: "Acceptance must know whether a package-admitted application update can still resume and append its structured event on MainActor."))
        #expect(body.contains("acceptanceSealInFlight"), Comment(rawValue: "A synchronous MainActor fence must close new application-update admission before the package seal await."))
    }

    @Test("application update marks itself in flight before suspending into package authority")
    func applicationMutationSpansPackageAwaitAndAppEventAppend() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let update = try section(
            in: app,
            from: "private func receivedApplicationUpdate",
            to: "private func startWatchdog"
        )
        let body = String(update)

        guard let admissionFence = body.range(of: "acceptanceSealInFlight"),
              let mutationBegin = body.range(of: "applicationUpdateMutationsInFlight += 1"),
              let packageMutation = body.range(of: "try await sessionLedger.recordApplicationUpdate"),
              let acceptedEvent = body.range(of: "log(\"tuya_application_update\"") else {
            Issue.record("Application updates must be fenced and counted across the package actor hop through the accepted app-event append.")
            throw SourceContractError.sectionMissing
        }

        #expect(admissionFence.lowerBound < mutationBegin.lowerBound)
        #expect(mutationBegin.lowerBound < packageMutation.lowerBound)
        #expect(packageMutation.lowerBound < acceptedEvent.lowerBound)
        #expect(body.contains("applicationUpdateMutationsInFlight -= 1"), Comment(rawValue: "The in-flight marker must retire on every terminal path only after the app-side mutation is finished."))
    }

    @Test("candidate accepted event prefix is frozen before the package seal await")
    func acceptedPrefixCutoffPrecedesPackageSealSuspension() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let noMutationGate = body.range(of: "applicationUpdateMutationsInFlight == 0"),
              let closeAdmission = body.range(of: "acceptanceSealInFlight = true", range: noMutationGate.upperBound..<body.endIndex),
              let frozenCandidate = body.range(of: "let acceptedEventPrefixCandidate = events", range: closeAdmission.upperBound..<body.endIndex),
              let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: frozenCandidate.upperBound..<body.endIndex),
              let publishFrozen = body.range(of: "sealedAcceptedEventPrefix = acceptedEventPrefixCandidate", range: packageSeal.upperBound..<body.endIndex) else {
            Issue.record("Acceptance must drain in-flight app mutations, close admission, freeze the candidate prefix synchronously, then await package seal and publish only on success.")
            throw SourceContractError.sectionMissing
        }

        #expect(noMutationGate.lowerBound < closeAdmission.lowerBound)
        #expect(closeAdmission.lowerBound < frozenCandidate.lowerBound)
        #expect(frozenCandidate.lowerBound < packageSeal.lowerBound)
        #expect(packageSeal.lowerBound < publishFrozen.lowerBound)
    }

    @Test("merged post-await mutable copy is forbidden")
    func packageSealCannotBeFollowedByMutableEventsCopy() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        #expect(!body.contains("try await sessionLedger.sealAcceptedObservation(for: token)\n                        self.sealedAcceptedEventPrefix = self.events"), Comment(rawValue: "Copying mutable app events only after the package seal await allows post-seal rejected diagnostics to enter the accepted prefix and package-admitted updates to miss it depending on actor continuation order."))
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
