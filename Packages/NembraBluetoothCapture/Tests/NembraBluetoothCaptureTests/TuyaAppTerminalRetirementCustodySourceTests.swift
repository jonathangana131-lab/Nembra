import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture app terminal-retirement custody")
struct TuyaAppTerminalRetirementCustodySourceTests {
    @Test("failed package retirement never clears app generation ownership")
    func failedRetirementKeepsExactTokenFence() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        // A swallowed no-clock terminal failure can strand package callback authority while the
        // app pretends the generation disappeared. Keep this forbidden globally in Entrypoint.
        #expect(!app.contains("try? await sessionLedger.markInternalLifecycleFailure(for: token)"))

        let internalLifecycle = try function(in: app, startingAt: "private func invalidateInternalLifecycle")
        #expect(internalLifecycle.contains("try await sessionLedger.markInternalLifecycleFailure(for: token)"))
        #expect(internalLifecycle.contains("catch {"))
        #expect(internalLifecycle.contains("internal_lifecycle_terminal_retirement_failed"))

        guard let terminalCall = internalLifecycle.range(of: "try await sessionLedger.markInternalLifecycleFailure(for: token)"),
              let catchRange = internalLifecycle.range(of: "catch {", range: terminalCall.upperBound..<internalLifecycle.endIndex),
              let clearRange = internalLifecycle.range(of: "currentConnectionToken = nil", range: catchRange.upperBound..<internalLifecycle.endIndex),
              let failedReturn = internalLifecycle.range(of: "return", range: catchRange.upperBound..<clearRange.lowerBound) else {
            Issue.record("Could not prove package-retirement failure returns before app token ownership is cleared.")
            return
        }

        #expect(failedReturn.lowerBound < clearRange.lowerBound)
    }

    @Test("all fallback terminal helpers preserve custody when no-clock retirement fails")
    func fallbackTerminalsDoNotSwallowRetirementFailure() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helperMarkers = [
            "private func authenticationAcquisitionFailed",
            "private func recordObservedTransportLoss",
            "private func invalidateSourceAuthority",
            "private func invalidateObservationContinuity",
        ]

        for marker in helperMarkers {
            let helper = try function(in: app, startingAt: marker)
            #expect(helper.contains("try await sessionLedger.markInternalLifecycleFailure(for: token)"), "\(marker) must retain a clock-independent fallback terminal.")
            #expect(!helper.contains("try? await sessionLedger.markInternalLifecycleFailure(for: token)"), "\(marker) must not swallow failed package retirement.")
            #expect(helper.contains("terminal_retirement_failed"), "\(marker) must expose failed retirement instead of hiding ownership loss.")
        }
    }

    private func function(in source: String, startingAt marker: String) throws -> Substring {
        guard let markerRange = source.range(of: marker),
              let openingBrace = source[markerRange.upperBound...].firstIndex(of: "{") else {
            Issue.record("Expected source function missing: \(marker)")
            throw SourceContractError.functionMissing
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return source[markerRange.lowerBound...index] }
            default: break
            }
            index = source.index(after: index)
        }

        Issue.record("Expected balanced source function body: \(marker)")
        throw SourceContractError.functionMissing
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
        case functionMissing
    }
}
