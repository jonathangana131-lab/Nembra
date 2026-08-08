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

old_hero_status = '''            HStack(spacing: 10) {
                Image(systemName: statusSymbol(for: phase))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor(for: phase))
                    .accessibilityHidden(true)

                Text(statusTitle(for: phase))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                Text("PASSIVE / READ ONLY")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
            }
'''
new_hero_status = '''            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: statusSymbol(for: phase))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(statusColor(for: phase))
                            .accessibilityHidden(true)

                        Text(statusTitle(for: phase))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("PASSIVE / READ ONLY")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: statusSymbol(for: phase))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusColor(for: phase))
                        .accessibilityHidden(true)

                    Text(statusTitle(for: phase))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer(minLength: 8)

                    Text("PASSIVE / READ ONLY")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
'''
shell = replace_once(shell, old_hero_status, new_hero_status, "adaptive hero status")

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
shell = replace_once(shell, old_progress, new_progress, "adaptive progress rail")

primary_anchor = '''    @ViewBuilder
    private func primaryContent(
'''
progress_helpers = '''    private func accessibilityProgressStage(
        index: Int,
        completedWindows: Int,
        currentWindow: Int?,
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
shell = replace_once(shell, primary_anchor, progress_helpers + primary_anchor, "progress helpers")

old_health = '''        return HStack(spacing: 12) {
            healthItem("TARGET", value: connection == .connected ? "BOUND" : "WAIT")
            Divider().frame(height: 28).overlay(.white.opacity(0.12))
            healthItem("DISCOVERY", value: observationReady ? "READY" : "WAIT")
            Divider().frame(height: 28).overlay(.white.opacity(0.12))
            healthItem("SEAL", value: horizonReady ? "READY" : "HOLD")
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Capture health. Target \\(connection == .connected ? "bound" : "waiting"). Passive discovery \\(observationReady ? "ready" : "waiting"). Seal \\(horizonReady ? "ready" : "waiting")."
        )
'''
new_health = '''        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    healthItem("TARGET", value: connection == .connected ? "BOUND" : "WAIT")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider().overlay(.white.opacity(0.12))
                    healthItem("DISCOVERY", value: observationReady ? "READY" : "WAIT")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider().overlay(.white.opacity(0.12))
                    healthItem("SEAL", value: horizonReady ? "READY" : "HOLD")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 12) {
                    healthItem("TARGET", value: connection == .connected ? "BOUND" : "WAIT")
                    Divider().frame(height: 28).overlay(.white.opacity(0.12))
                    healthItem("DISCOVERY", value: observationReady ? "READY" : "WAIT")
                    Divider().frame(height: 28).overlay(.white.opacity(0.12))
                    healthItem("SEAL", value: horizonReady ? "READY" : "HOLD")
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Capture health. Target \\(connection == .connected ? "bound" : "waiting"). Passive discovery \\(observationReady ? "ready" : "waiting"). Seal \\(horizonReady ? "ready" : "waiting")."
        )
        .accessibilityIdentifier("es80.capture.health")
'''
shell = replace_once(shell, old_health, new_health, "adaptive Capture health")
shell_path.write_text(shell)

ui_path = Path("NembraUITests/ES80ResearchCaptureUITests.swift")
ui = ui_path.read_text()
last_close = ui.rfind("\n}")
if last_close < 0:
    raise RuntimeError("UI test class closing brace not found")

new_tests = r'''

    @MainActor
    func testV14SimulatorQAHorizonReadyDynamicTypeSurfacesRemainReviewableAtAccessibilityExtraExtraExtraLarge() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let passiveMode = app.staticTexts["PASSIVE / READ ONLY"]
        let progress = app.descendants(matching: .any)["es80.capture.experiment-progress"]
        let health = app.descendants(matching: .any)["es80.capture.health"]
        let finish = app.descendants(matching: .any)["es80.capture.finish"]

        XCTAssertTrue(app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 5))
        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(passiveMode.waitForExistence(timeout: 3))
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertTrue(health.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)

        let topFrame = app.windows.firstMatch.frame
        assertVisibleInScreenshotViewport(
            qaDisclosure,
            windowFrame: topFrame,
            context: "synthetic disclosure beside recomposed Capture hero at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            passiveMode,
            windowFrame: topFrame,
            context: "PASSIVE / READ ONLY hero state at Accessibility XXXL"
        )

        let heroAttachment = XCTAttachment(screenshot: app.screenshot())
        heroAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Hero — Accessibility XXXL"
        heroAttachment.lifetime = .keepAlways
        add(heroAttachment)

        for (element, context, name) in [
            (progress, "paired Capture progress rail at Accessibility XXXL", "Nembra Capture V14 — SIMULATOR QA — Progress — Accessibility XXXL"),
            (health, "stacked Capture health at Accessibility XXXL", "Nembra Capture V14 — SIMULATOR QA — Capture Health — Accessibility XXXL"),
            (finish, "Seal Capture remains reachable at Accessibility XXXL", "Nembra Capture V14 — SIMULATOR QA — Seal — Accessibility XXXL")
        ] {
            bringIntoScreenshotViewport(element, in: app, context: context)
            assertVisibleInScreenshotViewport(
                element,
                windowFrame: app.windows.firstMatch.frame,
                context: context
            )
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testV14SimulatorQAHorizonReadyProgressRemainsReviewableInLandscape() {
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
        XCTAssertGreaterThan(
            app.windows.firstMatch.frame.width,
            app.windows.firstMatch.frame.height,
            "The progress visual gate must actually run in landscape."
        )

        bringIntoScreenshotViewport(
            progress,
            in: app,
            context: "Capture progress rail in landscape"
        )
        assertVisibleInScreenshotViewport(
            progress,
            windowFrame: app.windows.firstMatch.frame,
            context: "Capture progress rail in landscape"
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
acceptance = Path(
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ES80CaptureDynamicTypeSourceAcceptanceTests.swift"
).read_text()
assert "CAPTURE PROGRESS" in shell
assert "EXPERIMENT ONE" not in shell.split("private func progressRail(", 1)[1].split("@ViewBuilder", 1)[0]
assert "@Environment(\\.dynamicTypeSize) private var dynamicTypeSize" in shell
assert "dynamicTypeSize.isAccessibilitySize" in shell
assert "ForEach(0..<3" in shell and "ForEach(3..<6" in shell
assert 'accessibilityIdentifier("es80.capture.health")' in shell
assert "testV14SimulatorQAHorizonReadyDynamicTypeSurfacesRemainReviewableAtAccessibilityExtraExtraExtraLarge" in ui
assert "testV14SimulatorQAHorizonReadyProgressRemainsReviewableInLandscape" in ui
assert "heroStatusRecomposes" in acceptance
assert "progressRailRecomposes" in acceptance
assert "captureHealthRecomposes" in acceptance
