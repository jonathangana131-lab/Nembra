from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one exact anchor, found {count}")
    return text.replace(old, new, 1)


shell_path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
shell = shell_path.read_text()

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

new_test = r'''

    @MainActor
    func testV14SimulatorQAHorizonReadyHeroAndHealthRecomposeAtAccessibilityExtraExtraExtraLarge() {
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
        let health = app.descendants(matching: .any)["es80.capture.health"]

        XCTAssertTrue(app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 5))
        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(passiveMode.waitForExistence(timeout: 3))
        XCTAssertTrue(health.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)

        let initialFrame = app.windows.firstMatch.frame
        assertVisibleInScreenshotViewport(
            qaDisclosure,
            windowFrame: initialFrame,
            context: "synthetic disclosure beside recomposed Capture hero at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            passiveMode,
            windowFrame: initialFrame,
            context: "PASSIVE / READ ONLY hero state at Accessibility XXXL"
        )

        let heroAttachment = XCTAttachment(screenshot: app.screenshot())
        heroAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Hero — Accessibility XXXL"
        heroAttachment.lifetime = .keepAlways
        add(heroAttachment)

        bringIntoScreenshotViewport(
            health,
            in: app,
            context: "stacked Capture health at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            health,
            windowFrame: app.windows.firstMatch.frame,
            context: "stacked Capture health at Accessibility XXXL"
        )

        let healthAttachment = XCTAttachment(screenshot: app.screenshot())
        healthAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Capture Health — Accessibility XXXL"
        healthAttachment.lifetime = .keepAlways
        add(healthAttachment)
    }
'''
ui = ui[:last_close] + new_test + ui[last_close:]
ui_path.write_text(ui)

# Fail closed before product commit.
shell = shell_path.read_text()
ui = ui_path.read_text()
acceptance = Path(
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ES80CaptureDynamicTypeSourceAcceptanceTests.swift"
).read_text()
hero_section = shell.split("private func hero(for phase:", 1)[1].split("#if DEBUG && targetEnvironment(simulator)", 1)[0]
health_section = shell.split("private func observationHealthStrip(", 1)[1].split("private var completionPanel", 1)[0]
assert "dynamicTypeSize.isAccessibilitySize" in hero_section
assert "PASSIVE / READ ONLY" in hero_section
assert "dynamicTypeSize.isAccessibilitySize" in health_section
assert "TARGET" in health_section and "DISCOVERY" in health_section and "SEAL" in health_section
assert 'accessibilityIdentifier("es80.capture.health")' in health_section
assert "testV14SimulatorQAHorizonReadyHeroAndHealthRecomposeAtAccessibilityExtraExtraExtraLarge" in ui
assert "Capture Health — Accessibility XXXL" in ui
assert "heroStatusRecomposes" in acceptance
assert "progressRailRecomposes" in acceptance
assert "captureHealthRecomposes" in acceptance
