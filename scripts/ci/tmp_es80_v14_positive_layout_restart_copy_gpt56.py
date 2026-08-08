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

old_restart = '''        do {
            coordinator = try onFreshExperimentRequested()
        } catch {
            localFailureMessage = "Nembra could not create a fresh package-owned Experiment One workflow: \\(String(describing: error))"
        }
'''
new_restart = '''        do {
            coordinator = try onFreshExperimentRequested()
        } catch {
            localFailureMessage = "Nembra could not start a fresh capture. Close and reopen Nembra, then try again."
        }
'''
shell = replace_once(shell, old_restart, new_restart, "fresh-run failure copy")
shell_path.write_text(shell)

ui_path = Path("NembraUITests/ES80ResearchCaptureUITests.swift")
ui = ui_path.read_text()
insertion_anchor = '''    @MainActor
    func testV14SimulatorQARendersCompleteAndShareRetryStates() {
'''
positive_methods = r'''    @MainActor
    func testV14SimulatorQAPositiveShellRemainsLegibleAtAccessibilityExtraExtraExtraLarge() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let simulatorBadge = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let progress = app.descendants(matching: .any)["es80.capture.experiment-progress"]
        let finish = app.descendants(matching: .any)["es80.capture.finish"]

        XCTAssertTrue(app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 5))
        XCTAssertTrue(simulatorBadge.waitForExistence(timeout: 3))
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)
        for label in ["OFF 1", "ON 1", "OFF 2", "ON 2", "READY", "SEAL"] {
            XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 2), "Missing positive Capture progress label: \(label)")
        }

        let windowFrame = app.windows.firstMatch.frame
        assertVisibleInScreenshotViewport(
            simulatorBadge,
            windowFrame: windowFrame,
            context: "positive synthetic-state disclosure at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            progress,
            windowFrame: windowFrame,
            context: "positive Capture progress rail at Accessibility XXXL"
        )

        let topAttachment = XCTAttachment(screenshot: app.screenshot())
        topAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready — Accessibility XXXL"
        topAttachment.lifetime = .keepAlways
        add(topAttachment)

        for _ in 0..<4 {
            if finish.frame.intersects(windowFrame) { break }
            app.swipeUp()
        }
        assertVisibleInScreenshotViewport(
            finish,
            windowFrame: windowFrame,
            context: "Seal Capture action at Accessibility XXXL"
        )

        let sealAttachment = XCTAttachment(screenshot: app.screenshot())
        sealAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Seal — Accessibility XXXL"
        sealAttachment.lifetime = .keepAlways
        add(sealAttachment)
    }

    @MainActor
    func testV14SimulatorQAPositiveShellLandscapeKeepsProgressAndSealVisible() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft

        let simulatorBadge = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let progress = app.descendants(matching: .any)["es80.capture.experiment-progress"]
        let finish = app.descendants(matching: .any)["es80.capture.finish"]
        XCTAssertTrue(simulatorBadge.waitForExistence(timeout: 3))
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)

        let windowFrame = app.windows.firstMatch.frame
        assertVisibleInScreenshotViewport(
            simulatorBadge,
            windowFrame: windowFrame,
            context: "positive synthetic-state disclosure in Landscape"
        )
        assertVisibleInScreenshotViewport(
            progress,
            windowFrame: windowFrame,
            context: "positive Capture progress rail in Landscape"
        )

        let topAttachment = XCTAttachment(screenshot: app.screenshot())
        topAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready — Landscape"
        topAttachment.lifetime = .keepAlways
        add(topAttachment)

        for _ in 0..<4 {
            if finish.frame.intersects(windowFrame) { break }
            app.swipeUp()
        }
        assertVisibleInScreenshotViewport(
            finish,
            windowFrame: windowFrame,
            context: "Seal Capture action in Landscape"
        )

        let sealAttachment = XCTAttachment(screenshot: app.screenshot())
        sealAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Seal — Landscape"
        sealAttachment.lifetime = .keepAlways
        add(sealAttachment)
    }

'''
ui = replace_once(ui, insertion_anchor, positive_methods + insertion_anchor, "positive layout UI tests")
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

        #expect(!restart.contains("package-owned"))
        #expect(!restart.contains("Experiment One workflow"))
        #expect(!restart.contains("String(describing: error)"))
        #expect(restart.contains("Nembra could not start a fresh capture."))
        #expect(restart.contains("Close and reopen Nembra"))
    }

'''
rider = replace_once(rider, rider_anchor, restart_test + rider_anchor, "restart copy acceptance")
rider_path.write_text(rider)

# Fail closed before the workflow commits anything if the intended product contract was not produced.
shell = shell_path.read_text()
ui = ui_path.read_text()
rider = rider_path.read_text()
assert "@Environment(\\.dynamicTypeSize) private var dynamicTypeSize" in shell
assert "if dynamicTypeSize.isAccessibilitySize" in shell
assert "Grid(horizontalSpacing: 20, verticalSpacing: 8)" in shell
restart = shell.split("private func restartExperiment()", 1)[1].split("private func handleScenePhaseChange", 1)[0]
assert "package-owned" not in restart
assert "String(describing: error)" not in restart
assert "Nembra could not start a fresh capture." in restart
for name in (
    "testV14SimulatorQAPositiveShellRemainsLegibleAtAccessibilityExtraExtraExtraLarge",
    "testV14SimulatorQAPositiveShellLandscapeKeepsProgressAndSealVisible",
):
    assert f"func {name}()" in ui
for marker in (
    "--es80-capture-qa-scenario=observationHorizonReady",
    "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
    "XCUIDevice.shared.orientation = .landscapeLeft",
    "es80.capture.simulator-qa",
    "es80.capture.experiment-progress",
    "es80.capture.finish",
    "assertVisibleInScreenshotViewport",
):
    assert marker in ui
assert "freshRunConstructionFailureCopyStaysHumanFirst" in rider
