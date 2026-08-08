from pathlib import Path

app_path = Path("NembraApp/App/NembraApp.swift")
shell_path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
tests_path = Path("NembraAppTests/NembraAppTests.swift")

app = app_path.read_text()
shell = shell_path.read_text()
tests = tests_path.read_text()

old = '''private struct ES80ExperimentOneStationaryPreflightView: View {
    let coordinator: PassiveBluetoothExperimentOneCoordinator

    @State private var selectedChargerState: PassiveBluetoothStationaryCaptureChargerState?
    @State private var disconnectedDeclarationAccepted = false

    var body: some View {
        if disconnectedDeclarationAccepted {
            ES80CaptureShellView(coordinator: coordinator)
        } else {
'''
new = '''private struct ES80ExperimentOneStationaryPreflightView: View {
    @State private var coordinator: PassiveBluetoothExperimentOneCoordinator?
    @State private var selectedChargerState: PassiveBluetoothStationaryCaptureChargerState?
    @State private var disconnectedDeclarationAccepted = false
    @State private var coordinatorCreationError: String?

    init(coordinator: PassiveBluetoothExperimentOneCoordinator) {
        _coordinator = State(initialValue: coordinator)
    }

    var body: some View {
        if disconnectedDeclarationAccepted, let coordinator {
            ES80CaptureShellView(
                coordinator: coordinator,
                onRequestFreshExperiment: resetForFreshExperiment
            )
        } else {
'''
if app.count(old) != 1:
    raise SystemExit("stationary preflight ownership block did not match exactly once")
app = app.replace(old, new, 1)

old = '''                    Button {
                        guard selectedChargerState?.rawValue
                                == PassiveBluetoothStationaryCaptureChargerState.disconnected.rawValue else {
                            return
                        }
                        disconnectedDeclarationAccepted = true
                    } label: {
'''
new = '''                    if let coordinatorCreationError {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Fresh capture unavailable")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text(coordinatorCreationError)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(18)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("es80.capture.preflight.coordinator-unavailable")
                    }

                    Button {
                        guard canContinue else { return }
                        disconnectedDeclarationAccepted = true
                    } label: {
'''
if app.count(old) != 1:
    raise SystemExit("preflight continue block did not match exactly once")
app = app.replace(old, new, 1)

old = '''    private var canContinue: Bool {
        selectedChargerState?.rawValue
            == PassiveBluetoothStationaryCaptureChargerState.disconnected.rawValue
    }

    private func chargerStateButton(
'''
new = '''    private var canContinue: Bool {
        selectedChargerState?.rawValue
            == PassiveBluetoothStationaryCaptureChargerState.disconnected.rawValue
            && coordinator != nil
            && coordinatorCreationError == nil
    }

    private func resetForFreshExperiment() {
        coordinator?.abandonExperiment()
        selectedChargerState = nil
        disconnectedDeclarationAccepted = false
        coordinatorCreationError = nil

        do {
            coordinator = try PassiveBluetoothExperimentOneCoordinator()
        } catch {
            coordinator = nil
            coordinatorCreationError = "Nembra could not create a fresh Experiment One workflow. Close Capture and try again before starting another run."
        }
    }

    private func chargerStateButton(
'''
if app.count(old) != 1:
    raise SystemExit("preflight canContinue block did not match exactly once")
app = app.replace(old, new, 1)

old = '''    @State private var showingDetails = false

    init(coordinator: PassiveBluetoothExperimentOneCoordinator) {
        _coordinator = State(initialValue: coordinator)
    }
'''
new = '''    @State private var showingDetails = false

    private let onRequestFreshExperiment: () -> Void

    init(
        coordinator: PassiveBluetoothExperimentOneCoordinator,
        onRequestFreshExperiment: @escaping () -> Void
    ) {
        _coordinator = State(initialValue: coordinator)
        self.onRequestFreshExperiment = onRequestFreshExperiment
    }
'''
if shell.count(old) != 1:
    raise SystemExit("shell initializer block did not match exactly once")
shell = shell.replace(old, new, 1)

start_marker = '''    private func restartExperiment() {
        coordinator.abandonExperiment()
'''
end_marker = '''    private func handleScenePhaseChange(_ newScenePhase: ScenePhase) {
'''
start = shell.find(start_marker)
end = shell.find(end_marker, start)
if start == -1 or end == -1:
    raise SystemExit("shell restartExperiment boundaries not found")
shell = shell[:start] + '''    private func restartExperiment() {
        onRequestFreshExperiment()
    }

''' + shell[end:]

insert_before = '''    func testCaptureShellContinuesSameAuthorityThroughFinalShareIntegrity() throws {
'''
new_test = '''    func testEveryFreshCaptureReturnsThroughStationaryPreflight() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(
            contentsOf: root.appendingPathComponent("NembraApp/App/NembraApp.swift"),
            encoding: .utf8
        )
        let shell = try String(
            contentsOf: root.appendingPathComponent("NembraApp/Features/Research/ES80CaptureShellView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(app.contains("onRequestFreshExperiment: resetForFreshExperiment"))
        XCTAssertTrue(app.contains("selectedChargerState = nil"))
        XCTAssertTrue(app.contains("disconnectedDeclarationAccepted = false"))
        XCTAssertTrue(app.contains("coordinator = try PassiveBluetoothExperimentOneCoordinator()"))
        XCTAssertTrue(shell.contains("private let onRequestFreshExperiment: () -> Void"))
        XCTAssertTrue(shell.contains("onRequestFreshExperiment()"))
        XCTAssertFalse(
            shell.contains("coordinator = try PassiveBluetoothExperimentOneCoordinator()"),
            "A fresh run must be rebuilt by the parent preflight so charger state is declared again before OFF 1."
        )
    }

'''
if tests.count(insert_before) != 1:
    raise SystemExit("app test insertion point did not match exactly once")
tests = tests.replace(insert_before, new_test + insert_before, 1)

app_path.write_text(app)
shell_path.write_text(shell)
tests_path.write_text(tests)
