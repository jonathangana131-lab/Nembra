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

old_progress = '''            HStack(spacing: 6) {
                ForEach(0..<6, id: \\.self) { index in
                    Capsule(style: .continuous)
                        .fill(progressSegmentFill(
                            index: index,
                            completedWindows: completed,
                            currentWindow: current,
                            status: status
                        ))
                        .frame(height: 5)
                }
            }

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
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(.secondary)
'''
new_progress = '''            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \\.self) { index in
                            accessibilityProgressStage(
                                index: index,
                                completedWindows: completed,
                                currentWindow: current,
                                status: status
                            )
                        }
                    }

                    HStack(spacing: 8) {
                        ForEach(3..<6, id: \\.self) { index in
                            accessibilityProgressStage(
                                index: index,
                                completedWindows: completed,
                                currentWindow: current,
                                status: status
                            )
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(0..<6, id: \\.self) { index in
                        Capsule(style: .continuous)
                            .fill(progressSegmentFill(
                                index: index,
                                completedWindows: completed,
                                currentWindow: current,
                                status: status
                            ))
                            .frame(height: 5)
                    }
                }

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
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            }
'''
shell = replace_once(shell, old_progress, new_progress, "paired accessibility progress rail")

primary_anchor = '''    @ViewBuilder
    private func primaryContent(
'''
helper = '''    private func accessibilityProgressStage(
        index: Int,
        completedWindows: Int,
        currentWindow: PassiveBluetoothPowerCycleObservationPhase?,
        status: PassiveBluetoothExperimentOneCoordinator.Status
    ) -> some View {
        VStack(spacing: 6) {
            Capsule(style: .continuous)
                .fill(progressSegmentFill(
                    index: index,
                    completedWindows: completedWindows,
                    currentWindow: currentWindow,
                    status: status
                ))
                .frame(height: 5)

            Text(progressStageLabel(index: index))
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func progressStageLabel(index: Int) -> String {
        switch index {
        case 0: "OFF 1"
        case 1: "ON 1"
        case 2: "OFF 2"
        case 3: "ON 2"
        case 4: "READY"
        case 5: "SEAL"
        default: ""
        }
    }

'''
shell = replace_once(shell, primary_anchor, helper + primary_anchor, "accessibility progress helper")
shell_path.write_text(shell)

ui_path = Path("NembraUITests/ES80ResearchCaptureUITests.swift")
ui = ui_path.read_text()
last_close = ui.rfind("\n}")
if last_close < 0:
    raise RuntimeError("UI test class closing brace not found")

new_tests = r'''

    @MainActor
    func testV14SimulatorQAHorizonReadyProgressIsReviewableAtAccessibilityExtraExtraExtraLarge() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let progress = app.descendants(matching: .any)["es80.capture.experiment-progress"]
        let finish = app.descendants(matching: .any)["es80.capture.finish"]

        XCTAssertTrue(app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 5))
        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)

        bringIntoScreenshotViewport(
            progress,
            in: app,
            context: "paired positive Capture progress rail at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            progress,
            windowFrame: app.windows.firstMatch.frame,
            context: "paired positive Capture progress rail at Accessibility XXXL"
        )

        let progressAttachment = XCTAttachment(screenshot: app.screenshot())
        progressAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Paired Progress — Accessibility XXXL"
        progressAttachment.lifetime = .keepAlways
        add(progressAttachment)

        bringIntoScreenshotViewport(
            finish,
            in: app,
            context: "Seal Capture action after paired progress review at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            finish,
            windowFrame: app.windows.firstMatch.frame,
            context: "Seal Capture action after paired progress review at Accessibility XXXL"
        )

        let finishAttachment = XCTAttachment(screenshot: app.screenshot())
        finishAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Seal After Progress — Accessibility XXXL"
        finishAttachment.lifetime = .keepAlways
        add(finishAttachment)
    }

    @MainActor
    func testV14SimulatorQAHorizonReadyProgressIsReviewableInLandscape() {
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

        let progress = app.descendants(matching: .any)["es80.capture.experiment-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)

        let landscapeFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(
            landscapeFrame.width,
            landscapeFrame.height,
            "The progress visual gate must actually run in landscape."
        )
        bringIntoScreenshotViewport(
            progress,
            in: app,
            context: "positive Capture progress rail in landscape"
        )
        assertVisibleInScreenshotViewport(
            progress,
            windowFrame: app.windows.firstMatch.frame,
            context: "positive Capture progress rail in landscape"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — SIMULATOR QA — Progress Rail — Landscape"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
'''
ui = ui[:last_close] + new_tests + ui[last_close:]
ui_path.write_text(ui)

# Fail closed before any product commit.
shell = shell_path.read_text()
ui = ui_path.read_text()
assert "@Environment(\\.dynamicTypeSize) private var dynamicTypeSize" in shell
assert "if dynamicTypeSize.isAccessibilitySize" in shell
assert "ForEach(0..<3" in shell and "ForEach(3..<6" in shell
assert "accessibilityProgressStage" in shell
assert "progressStageLabel(index: index)" in shell
assert "testV14SimulatorQAHorizonReadyProgressIsReviewableAtAccessibilityExtraExtraExtraLarge" in ui
assert "testV14SimulatorQAHorizonReadyProgressIsReviewableInLandscape" in ui
assert '"es80.capture.experiment-progress"' in ui
assert "Paired Progress — Accessibility XXXL" in ui
assert "Progress Rail — Landscape" in ui
