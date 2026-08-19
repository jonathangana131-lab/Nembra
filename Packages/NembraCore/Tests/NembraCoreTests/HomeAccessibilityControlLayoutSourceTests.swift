import Foundation
import Testing

@Suite("Home accessibility control layout source")
struct HomeAccessibilityControlLayoutSourceTests {
    @Test("Accessibility Dynamic Type reflows Home actions and the verified mode selector")
    func adaptiveActionAndModeControls() throws {
        let source = try String(contentsOf: homeViewURL, encoding: .utf8)

        #expect(source.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(source.contains("GlassEffectContainer(spacing: 14)"))
        #expect(source.contains("VStack(spacing: 0)"))
        #expect(source.contains("HStack(spacing: 0)"))
        #expect(source.contains("railDivider"))
        #expect(source.contains("ForEach(supportedModes, id: \\.self)"))
        #expect(source.contains("home.mode.selector"))
        #expect(source.contains("Open Horizon Dashboard"))
        #expect(!source.contains(".accessibilityIdentifier(\"home.controls\")"))
        #expect(source.contains(".frame(minHeight: 110)"))
        #expect(source.contains(".frame(minHeight: 96)"))
        #expect(source.contains(".modifier(HomeControlIconGlassModifier())"))
        #expect(source.contains(".glassEffect(.regular.interactive(isEnabled), in: .circle)"))
        #expect(source.contains("@Environment(\\.colorSchemeContrast) private var colorSchemeContrast"))
        #expect(source.contains("@Environment(\\.accessibilityShowBorders) private var showBorders"))
        #expect(source.contains("strongBoundaryRequested"))
        #expect(!source.contains("Text(available ? subtitle : \"Unavailable\")\n                        .font(.caption)\n                        .foregroundStyle(.secondary)\n                        .lineLimit(1)"))
        #expect(!source.contains(".frame(height: 58)\n            .frame(maxWidth: .infinity)"))

        let controlButtonStart = try #require(source.range(of: "private func controlButton("))
        let unavailableControlStart = try #require(
            source.range(
                of: "private func unavailableControl(",
                range: controlButtonStart.upperBound..<source.endIndex
            )
        )
        let controlButton = String(source[controlButtonStart.lowerBound..<unavailableControlStart.lowerBound])
        #expect(controlButton.contains("return Button(action: action)"))
        #expect(controlButton.contains(".accessibilityValue(pending ? \"Requesting confirmation\" : \"\")"))
        #expect(controlButton.contains(".modifier(HomeControlIconGlassModifier())"))
        #expect(!controlButton.contains(".nembraGlassControl()"))
        #expect(!controlButton.contains(".accessibilityElement(children: .ignore)"))
    }

    @Test("Home command semantics remain confirmation-backed and fail closed")
    func commandSemanticsRemainTruthful() throws {
        let source = try String(contentsOf: homeViewURL, encoding: .utf8)

        #expect(source.contains("@State private var pendingLockConfirmation: Bool?"))
        #expect(source.contains("pendingLockConfirmation = !locked"))
        #expect(source.contains("isLockConfirmationStillValid(requestedLocked)"))
        #expect(source.contains("vehicle.state.connection == .connected"))
        #expect(source.contains("!vehicle.isVehicleCommandPending"))
        #expect(source.contains("vehicle.canLockFromCurrentSpeedEvidence"))
        #expect(source.contains("vehicle.simulatorQualifiedLiveSpeedKilometersPerHour"))
        #expect(source.contains("Requesting confirmation"))
        #expect(source.contains("Task { await vehicle.setMode(mode) }"))
        #expect(source.contains("vehicle.state.rideMode == mode"))
        #expect(!source.contains(".sensoryFeedback(.selection, trigger: vehicle.state.rideMode)"))
    }

    private var homeViewURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NembraApp/Features/Home/HomeView.swift")
    }
}
