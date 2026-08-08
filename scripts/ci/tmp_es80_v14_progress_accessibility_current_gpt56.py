from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one exact anchor, found {count}")
    return text.replace(old, new, 1)


shell_path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
shell = shell_path.read_text()

scene_anchor = "    @Environment(\\.scenePhase) private var scenePhase\n"
shell = replace_once(
    shell,
    scene_anchor,
    scene_anchor + "    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n",
    "dynamic type environment",
)

old_labels = '''            HStack {
                Text("OFF 1")
                Spacer()
                Text("ON 1")
                Spacer()
                Text("OFF 2")
                Spacer()
                Text("ON 2")
                Spacer()
                Text("READY")
                Spacer()
                Text("SEAL")
            }
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(.secondary)
'''
new_labels = '''            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Grid(horizontalSpacing: 20, verticalSpacing: 8) {
                        GridRow {
                            Text("OFF 1")
                            Text("ON 1")
                            Text("OFF 2")
                        }
                        GridRow {
                            Text("ON 2")
                            Text("READY")
                            Text("SEAL")
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack {
                        Text("OFF 1")
                        Spacer()
                        Text("ON 1")
                        Spacer()
                        Text("OFF 2")
                        Spacer()
                        Text("ON 2")
                        Spacer()
                        Text("READY")
                        Spacer()
                        Text("SEAL")
                    }
                }
            }
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(.secondary)
'''
shell = replace_once(shell, old_labels, new_labels, "adaptive progress labels")

old_restart = '            localFailureMessage = "Nembra could not create a fresh Experiment One run: \\(String(describing: error))"\n'
new_restart = '            localFailureMessage = "Nembra could not start a fresh capture. Close and reopen Nembra, then try again."\n'
shell = replace_once(shell, old_restart, new_restart, "fresh-run failure copy")
shell_path.write_text(shell)

ui_path = Path("NembraUITests/ES80ResearchCaptureUITests.swift")
ui = ui_path.read_text()

ui = replace_once(
    ui,
    '''        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let completeState = app.staticTexts["CAPTURE COMPLETE"]
        let shareCapture = app.buttons["Share Capture"]
''',
    '''        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let progress = app.descendants(matching: .any)["es80.capture.experiment-progress"]
        let completeState = app.staticTexts["CAPTURE COMPLETE"]
        let shareCapture = app.buttons["Share Capture"]
''',
    "Accessibility XXXL progress element",
)
ui = replace_once(
    ui,
    '''        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 5))
        XCTAssertTrue(completeState.waitForExistence(timeout: 3))
''',
    '''        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 5))
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertTrue(completeState.waitForExistence(timeout: 3))
''',
    "Accessibility XXXL progress existence",
)
ui = replace_once(
    ui,
    '''        assertVisibleInScreenshotViewport(
            completeState,
            windowFrame: windowFrame,
            context: "Capture Complete state at Accessibility XXXL"
        )
''',
    '''        assertVisibleInScreenshotViewport(
            progress,
            windowFrame: windowFrame,
            context: "positive Capture progress rail at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            completeState,
            windowFrame: windowFrame,
            context: "Capture Complete state at Accessibility XXXL"
        )
''',
    "Accessibility XXXL progress viewport",
)

ui = replace_once(
    ui,
    '''        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let readyState = app.staticTexts["Capture can be sealed"]
        let finish = app.descendants(matching: .any)["es80.capture.finish"]
''',
    '''        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let progress = app.descendants(matching: .any)["es80.capture.experiment-progress"]
        let readyState = app.staticTexts["Capture can be sealed"]
        let finish = app.descendants(matching: .any)["es80.capture.finish"]
''',
    "landscape progress element",
)
ui = replace_once(
    ui,
    '''        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(readyState.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
''',
    '''        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertTrue(readyState.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
''',
    "landscape progress existence",
)
ui = replace_once(
    ui,
    '''        assertVisibleInScreenshotViewport(
            readyState,
            windowFrame: windowFrame,
            context: "Horizon-ready state in landscape"
        )
''',
    '''        assertVisibleInScreenshotViewport(
            progress,
            windowFrame: windowFrame,
            context: "positive Capture progress rail in landscape"
        )
        assertVisibleInScreenshotViewport(
            readyState,
            windowFrame: windowFrame,
            context: "Horizon-ready state in landscape"
        )
''',
    "landscape progress viewport",
)
ui_path.write_text(ui)

rider_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ES80CaptureRiderLanguageAcceptanceTests.swift")
rider = rider_path.read_text()
rider_anchor = '''    @Test("engineering truth remains available in Details instead of being deleted")
'''
restart_test = r'''    @Test("fresh-run construction failures stay bounded and rider-readable")
    func freshRunConstructionFailureCopyStaysHumanFirst() throws {
        let source = try Self.shellSource()
        let beginning = try #require(source.range(of: "private func restartExperiment()"))
        let end = try #require(
            source.range(
                of: "private func handleScenePhaseChange",
                range: beginning.lowerBound..<source.endIndex
            )
        )
        let restart = source[beginning.lowerBound..<end.lowerBound]

        #expect(!restart.contains("Experiment One"))
        #expect(!restart.contains("String(describing: error)"))
        #expect(restart.contains("Nembra could not start a fresh capture."))
        #expect(restart.contains("Close and reopen Nembra"))
    }

'''
rider = replace_once(rider, rider_anchor, restart_test + rider_anchor, "restart copy acceptance")
rider_path.write_text(rider)

shell = shell_path.read_text()
ui = ui_path.read_text()
rider = rider_path.read_text()
assert "@Environment(\\.dynamicTypeSize) private var dynamicTypeSize" in shell
assert "if dynamicTypeSize.isAccessibilitySize" in shell
assert "Grid(horizontalSpacing: 20, verticalSpacing: 8)" in shell
restart = shell.split("private func restartExperiment()", 1)[1].split("private func handleScenePhaseChange", 1)[0]
assert "Experiment One" not in restart
assert "String(describing: error)" not in restart
assert "Nembra could not start a fresh capture." in restart
assert ui.count('let progress = app.descendants(matching: .any)["es80.capture.experiment-progress"]') >= 2
assert 'context: "positive Capture progress rail at Accessibility XXXL"' in ui
assert 'context: "positive Capture progress rail in landscape"' in ui
assert "freshRunConstructionFailureCopyStaysHumanFirst" in rider
