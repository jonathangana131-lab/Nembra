from pathlib import Path

app_path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = app_path.read_text()


def replace_once(old: str, new: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one match, got {count}: {old[:120]!r}")
    source = source.replace(old, new, 1)


replace_once(
    "case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed",
    "case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed",
)
replace_once(
    "    @Published private(set) var selectedID: UUID?\n    @Published private(set) var sdkLocalBLEOnline = false",
    "    @Published private(set) var selectedID: UUID?\n    @Published private(set) var correlatedCandidateID: UUID?\n    @Published private(set) var sdkLocalBLEOnline = false",
)
replace_once(
    "    var selected: Candidate? { selectedID.flatMap { byID[$0] } }\n    var applicationUpdateCount: Int",
    "    var selected: Candidate? { selectedID.flatMap { byID[$0] } }\n    var correlatedCandidate: Candidate? { correlatedCandidateID.flatMap { byID[$0] } }\n    var applicationUpdateCount: Int",
)
replace_once(
    '''            selectedID = id
            correlationSession = nil
            phase = .selected
            message = "Fresh repeated power-cycle correlation found one full CoreBluetooth target. This is current-session correlation evidence, not permanent scooter identity. Discovery is retired before Tuya's SDK takes BLE ownership."
            log("candidate_selected", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])''',
    '''            correlatedCandidateID = id
            selectedID = nil
            correlationSession = nil
            phase = .correlated
            message = "Fresh repeated power-cycle correlation found one full CoreBluetooth target. Confirm this current-session correlation evidence before it can become the selected target. It is not permanent scooter identity."
            log("candidate_correlated", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id-pending-operator-confirmation",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])''',
)

confirmation = '''
    func confirmCorrelatedTarget() {
        guard phase == .correlated,
              let id = correlatedCandidateID,
              let candidate = byID[id],
              candidate.freshlyCorrelated else {
            failLocally(
                "No fresh current-session correlated Bluetooth target is waiting for confirmation. Restart from OFF1.",
                "correlated_target_confirmation_unavailable"
            )
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            failLocally(
                "Tuya account/device source authority changed before target confirmation. Restart from OFF1 after re-verifying membership.",
                "sdk_authority_changed_before_target_confirmation"
            )
            return
        }

        selectedID = id
        phase = .selected
        message = "Correlated Bluetooth target confirmed for this current session. This explicit selection authorizes only the local target handoff to Tuya's SDK; it does not establish permanent ES80 identity."
        log("candidate_selected", [
            "id": id.uuidString,
            "authority": "operator-confirmed-current-session-correlation",
            "historicalCaptureUUIDMatch": String(candidate.historicalCaptureID)
        ])
    }

'''
replace_once(
    "    func invalidateSDKMembership() {",
    confirmation + "    func invalidateSDKMembership() {",
)
replace_once(
    "        if [.baseline, .powerOn, .scanning, .selected].contains(phase) {",
    "        if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {",
)
replace_once(
    "        selectedID = nil\n        sdkLocalBLEOnline = false",
    "        selectedID = nil\n        correlatedCandidateID = nil\n        sdkLocalBLEOnline = false",
)
replace_once(
    '''            case .powerOn:
                Text("Next: \\(test.correlationWindowLabel) · \\(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \\(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            default:''',
    '''            case .powerOn:
                Text("Next: \\(test.correlationWindowLabel) · \\(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \\(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            case .correlated:
                if let candidate = test.correlatedCandidate {
                    Text("One correlated Bluetooth target is ready for explicit confirmation. This is current-session correlation evidence, not permanent scooter identity.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(candidate.id.uuidString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Button("Confirm correlated Bluetooth target") { test.confirmCorrelatedTarget() }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            !test.sdkAccountLoggedIn
                                || !test.sdkDeviceMembershipVerified
                                || !test.accountIdentityLeaseIsAuthorized
                                || test.membershipBusy
                        )
                }

            default:''',
)

app_path.write_text(source)

test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaExplicitCorrelatedTargetConfirmationSourceTests.swift")
test_path.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture explicit correlated-target confirmation")
struct TuyaExplicitCorrelatedTargetConfirmationSourceTests {
    @Test("unique repeated correlation is offered for confirmation instead of auto-selected")
    func correlationResultCannotAutoSelectTarget() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let finish = try section(
            in: app,
            from: "private func finishCorrelationSeries",
            to: "func invalidateSDKMembership"
        )

        #expect(finish.contains("singleRepeatableCandidate"))
        #expect(!finish.contains("selectedID = id"))
        #expect(!finish.contains("phase = .selected"))
        #expect(!finish.contains("candidate_selected"))
    }

    @Test("operator action is the only bridge from correlated candidate to selected target")
    func explicitOperatorConfirmationOwnsSelection() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("func confirmCorrelatedTarget"))
        let confirmation = try section(
            in: app,
            from: "func confirmCorrelatedTarget",
            to: "func invalidateSDKMembership"
        )
        #expect(confirmation.contains("selectedID"))
        #expect(confirmation.contains("phase = .selected"))
        #expect(confirmation.contains("candidate_selected"))
        #expect(confirmation.contains("correlation"))
    }

    @Test("primary UI exposes explicit confirmation before authentication")
    func primaryUIRequiresConfirmation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let discoveryCard = try section(
            in: app,
            from: "private var discoveryCard: some View",
            to: "private func authenticationCard"
        )
        #expect(discoveryCard.contains("confirmCorrelatedTarget"))
        #expect(discoveryCard.localizedCaseInsensitiveContains("confirm"))
        #expect(discoveryCard.localizedCaseInsensitiveContains("correlat"))
    }

    @Test("authentication still requires the explicitly selected current-session candidate")
    func authenticationConsumesConfirmedSelection() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticate = try section(
            in: app,
            from: "func authenticate()",
            to: "private func beginOfficialConnection"
        )
        #expect(authenticate.contains("selected"))
        #expect(authenticate.contains("candidate.likely"))
        #expect(authenticate.contains("verifySDKMembership"))
        #expect(authenticate.contains("accountIdentityLeaseIsAuthorized"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \\(start) ... \\(end)")
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
''')

Path(".github/workflows/v14-capture-explicit-confirmation-patch.yml").unlink()
Path("scripts/ci/v14_capture_explicit_confirmation_patch.py").unlink()
