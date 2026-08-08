from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 anchor, found {count}")
    return text.replace(old, new, 1)

app_path = Path("NembraApp/App/NembraApp.swift")
app = app_path.read_text()

app = app.replace('detail: "Required for ES80-FINGERPRINT-v1"', 'detail: "Required before capture"')
app = app.replace('detail: "Experiment One remains blocked"', 'detail: "Disconnect before continuing"')
app = app.replace('Text("Declare the scooter charger state before Experiment One can expose OFF 1.")', 'Text("Confirm the scooter is unplugged before starting Experiment One.")')
app = app.replace(
    'Text("The accepted stationary fingerprint recipe requires the scooter charger disconnected. Nembra will not convert a connected declaration into disconnected provenance. Unplug the charger, then select Disconnected.")',
    'Text("This capture must start with the scooter unplugged. Disconnect the charger, then select Disconnected.")'
)
app = app.replace(
    'Text("This is an operator declaration, not charger sensing or proof that the condition remains unchanged. Keep the charger disconnected, Nembra foregrounded with the screen unlocked, and the stock scooter app closed through the run.")',
    'Text("This check comes from your selection; Nembra does not sense the charger connection. Keep the charger disconnected, Nembra open with the screen unlocked, and the scooter’s other app closed until capture finishes.")'
)

app = replace_once(
    app,
    '''private struct ES80ExperimentOneFieldNoGoView: View {
    private var recipeID: String {
        PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue
    }

    private var physicalLockAccessibilityLabel: String {
        "Physical Experiment One locked. Nembra will not expose the OFF and ON field controls until the final composed app, lifecycle authority, provenance, runtime, visual, accessibility, performance, and runbook gates have all earned a deliberate GO authorization."
    }''',
    '''private struct ES80ExperimentOneFieldNoGoView: View {
    private var physicalLockAccessibilityLabel: String {
        "Real scooter capture unavailable. This build is still locked. Nembra will only unlock the guided OFF and ON procedure after this exact build is approved for field use."
    }''',
    "NO-GO authority intro",
)
app = app.replace('Text("This exact build is not authorized to begin the physical ES80 procedure.")', 'Text("This build isn’t approved for a real ES80 capture yet.")')
app = app.replace('Text("Physical Experiment One locked")', 'Text("Real scooter capture unavailable")')
app = app.replace(
    'Text("Nembra will not expose the OFF/ON field controls until the final composed app, lifecycle authority, provenance, runtime, visual, accessibility, performance, and runbook gates have all earned a deliberate GO authorization.")',
    'Text("Nembra will unlock the guided OFF/ON procedure only after this exact build passes the required safety and quality checks.")'
)
app = app.replace('Text("PROCEDURE")', 'Text("EXPERIMENT")')
app = replace_once(
    app,
    '''                    Text(recipeID)
                        .font(.title3.monospaced().weight(.semibold))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("es80.capture.recipe-id")''',
    '''                    Text("Experiment One")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("es80.capture.experiment-name")

                    Text("Stationary scooter fingerprint")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)''',
    "visible recipe token",
)
app = app.replace('Text("Single-authority workflow installed")', 'Text("Capture workflow ready")')
app = app.replace('Text("Field execution unavailable on this build")', 'Text("Real scooter capture locked")')
app = app.replace(
    'Text("No physical action is required. A future accepted build must unlock this mechanically from package-owned authorization; a UI flag, typed identifier, or local preference cannot do it.")',
    'Text("No action is needed right now. Nembra will unlock this screen only when the exact installed build is approved for a real scooter capture.")'
)
app_path.write_text(app)

ui_path = Path("NembraUITests/ES80ResearchCaptureUITests.swift")
ui = ui_path.read_text()
ui = ui.replace(
    '''        XCTAssertTrue(
            app.staticTexts["ES80-FINGERPRINT-v1"].waitForExistence(timeout: 3),
            "The installed versioned procedure must be identified without becoming executable."
        )''',
    '''        XCTAssertTrue(
            app.staticTexts["Experiment One"].waitForExistence(timeout: 3),
            "The rider-facing experiment identity must stay visible without exposing the raw recipe token."
        )
        XCTAssertFalse(
            app.staticTexts["ES80-FINGERPRINT-v1"].exists,
            "The raw recipe identifier belongs in engineering evidence, not the primary rider-facing locked state."
        )'''
)
ui = ui.replace('let recipe = app.staticTexts["ES80-FINGERPRINT-v1"]', 'let experiment = app.staticTexts["Experiment One"]')
ui = ui.replace('XCTAssertTrue(recipe.waitForExistence(timeout: 3))', 'XCTAssertTrue(experiment.waitForExistence(timeout: 3))')
ui = ui.replace('XCTAssertTrue(recipe.frame.height > 0)', 'XCTAssertTrue(experiment.frame.height > 0)')
ui = ui.replace('for element in [lockedState, physicalBoundary, recipe] {', 'for element in [lockedState, physicalBoundary, experiment] {')
ui = ui.replace('XCTAssertGreaterThan(recipe.frame.height, 0)', 'XCTAssertGreaterThan(experiment.frame.height, 0)')
ui_path.write_text(ui)
