import Foundation
import SwiftUI

struct CapturePresentationDisclosureBanner: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let text: String
    let accessibilityIdentifier: String

    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        Label {
            Text(text)
                .font(.caption.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.orange)
        .padding(.horizontal, 16)
        .padding(.vertical, isCompactHeight ? 8 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.97))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.orange.opacity(0.75))
                .frame(height: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(text)
    }
}

#if DEBUG && targetEnvironment(simulator)
enum CaptureSimulatorQAScenario: String, CaseIterable {
    case safety
    case correlationNone = "correlation-none"
    case correlationAmbiguous = "correlation-ambiguous"
    case correlationSuccess = "correlation-success"
    case observationActive = "observation-active"
    case observationTimeout = "observation-timeout"
    case observationCancelled = "observation-cancelled"
    case integrityPending = "integrity-pending"
    case complete
    case shareRetry = "share-retry"

    var title: String {
        switch self {
        case .safety:
            return "Stationary safety"
        case .correlationNone:
            return "No correlated signal"
        case .correlationAmbiguous:
            return "Ambiguous signals"
        case .correlationSuccess:
            return "Scooter signal found"
        case .observationActive:
            return "Read-only observation"
        case .observationTimeout:
            return "Observation timeout"
        case .observationCancelled:
            return "Observation cancelled"
        case .integrityPending:
            return "Sealed presentation"
        case .complete:
            return "Complete presentation"
        case .shareRetry:
            return "Share recovery"
        }
    }
}

enum CaptureSimulatorQALaunchSelection {
    case publicRoot
    case scenario(CaptureSimulatorQAScenario)
    case invalid(String)
}

enum CaptureSimulatorQALaunch {
    static let argument = "--nembra-capture-simulator-ui"

    static func selection(arguments: [String]) -> CaptureSimulatorQALaunchSelection {
        let matches = arguments.indices.filter { arguments[$0] == argument }
        guard !matches.isEmpty else { return .publicRoot }
        guard matches.count == 1 else { return .invalid("duplicate scenario argument") }

        let valueIndex = arguments.index(after: matches[0])
        guard arguments.indices.contains(valueIndex) else {
            return .invalid("missing scenario value")
        }

        let rawValue = arguments[valueIndex]
        guard let scenario = CaptureSimulatorQAScenario(rawValue: rawValue) else {
            return .invalid(rawValue)
        }
        return .scenario(scenario)
    }
}

enum CaptureSimulatorQADisclosure {
    static let text = "SIMULATOR QA · SYNTHETIC PRESENTATION · NO BLUETOOTH, TUYA, PHYSICAL OR PROTOCOL EVIDENCE"
    static let rootIdentifier = "nembra.capture.qa.synthetic-disclosure"
    static let sheetIdentifier = "nembra.capture.qa.synthetic-sheet-disclosure"
}

@MainActor
struct CaptureSimulatorQAHarness: View {
    private enum SheetDestination: Identifiable {
        case safety
        case share(attempt: Int)

        var id: String {
            switch self {
            case .safety:
                return "safety"
            case let .share(attempt):
                return "share-\(attempt)"
            }
        }
    }

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var scenario: CaptureSimulatorQAScenario
    @State private var presentedSheet: SheetDestination?
    @State private var shareAttemptCount = 0

    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    init(scenario: CaptureSimulatorQAScenario) {
        _scenario = State(initialValue: scenario)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                RadialGradient(
                    colors: [Color.orange.opacity(0.10), Color.clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 520
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: isCompactHeight ? 12 : 22) {
                        header
                        primarySurface
                    }
                    .frame(maxWidth: isCompactHeight ? 760 : 680, alignment: .leading)
                    .padding(.horizontal, isCompactHeight ? 16 : 20)
                    .padding(.top, isCompactHeight ? 8 : 18)
                    .padding(.bottom, isCompactHeight ? 24 : 44)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Capture QA")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                CapturePresentationDisclosureBanner(
                    text: CaptureSimulatorQADisclosure.text,
                    accessibilityIdentifier: CaptureSimulatorQADisclosure.rootIdentifier
                )
            }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .safety:
                StationarySafetyConfirmationSheet(
                    launch: .begin,
                    qaDisclosure: CaptureSimulatorQADisclosure.text
                ) {
                    scenario = .correlationSuccess
                }
            case let .share(attempt):
                CaptureSimulatorQAShareSurrogate(attempt: attempt)
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nembra.capture.qa.synthetic-root")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 4 : 7) {
            Text("SYNTHETIC PRIMARY FLOW")
                .font(.caption2.bold())
                .tracking(1.3)
                .foregroundStyle(.orange)
            Text(scenario.title)
                .font(isCompactHeight ? .title2.bold() : .largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(
                isCompactHeight
                    ? "Presentation and action routing only. It cannot authorize, observe, seal, or export a scooter capture."
                    : "This finite screen exercises presentation and action routing only. It cannot authorize, observe, seal, or export a scooter capture."
            )
                .font(isCompactHeight ? .callout : .body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var primarySurface: some View {
        switch scenario {
        case .safety:
            safetySurface
        case .correlationNone:
            stoppedSurface(
                kicker: "FIND SCOOTER · STOPPED",
                title: "No scooter signal matched",
                message: "No full UUID repeated the required OFF1→ON1→OFF2→ON2 pattern. Do not fall back to the historical capture UUID; restart the fresh correlation series.",
                identifier: "nembra.capture.correlation.outcome"
            )
        case .correlationAmbiguous:
            stoppedSurface(
                kicker: "FIND SCOOTER · STOPPED",
                title: "More than one signal matched",
                message: "Fresh correlation remained ambiguous across 2 repeatable full UUIDs. Do not guess from name, RSSI, FD50, or Tuya hints; restart from OFF1 after reducing nearby-device ambiguity.",
                identifier: "nembra.capture.correlation.outcome"
            )
        case .correlationSuccess:
            panel {
                CaptureCorrelationSuccessPresentation(isConfirmEnabled: true) {
                    scenario = .observationActive
                }
            }
        case .observationActive:
            observationSurface
        case .observationTimeout:
            stoppedSurface(
                kicker: "OBSERVATION · STOPPED",
                title: "Scooter data timed out",
                message: "Scooter data did not become sufficient before the bounded observation deadline. Keep the scooter stationary, relaunch Capture, and start again from scooter OFF.",
                identifier: "nembra.capture.observation.surface"
            )
        case .observationCancelled:
            stoppedSurface(
                kicker: "OBSERVATION · CANCELLED",
                title: "Attempt stopped",
                message: "The operator stopped this synthetic presentation. No observation, accepted state, or artifact carries forward.",
                identifier: "nembra.capture.observation.surface"
            )
        case .integrityPending:
            integrityPendingSurface
        case .complete, .shareRetry:
            completeSurface
        }
    }

    private var safetySurface: some View {
        panel {
            VStack(alignment: .leading, spacing: 18) {
                Label("Stationary safety check", systemImage: "hand.raised.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.cyan)
                Text("Open the real safety sheet presentation. Confirming advances only this local synthetic state.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    presentedSheet = .safety
                } label: {
                    Label("Review safety and begin", systemImage: "checkmark.shield.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("nembra.capture.stationary-safety-review")
            }
        }
    }

    private var observationSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            panel {
                VStack(alignment: .leading, spacing: 18) {
                    Text("OBSERVE")
                        .font(.caption2.bold())
                        .tracking(1.2)
                        .foregroundStyle(.cyan)
                    Text("Hold steady")
                        .font(.title2.bold())
                    Text("Keep Capture in the foreground and leave the scooter untouched until this read-only observation is complete.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Read-only observation")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("18 / 45 s")
                                .font(.subheadline.monospacedDigit().bold())
                        }
                        ProgressView(value: 18.0 / 45.0)
                            .accessibilityLabel("Read-only observation progress")
                            .accessibilityValue("18 of 45 seconds")
                        requirementRow("Secure local link", ready: true)
                        requirementRow("Repeated scooter data", ready: false)
                        requirementRow("Scooter data stayed live", ready: false)
                    }

                    CaptureStopConditionPresentation(
                        accessibilityHint: "Stops only this local synthetic presentation; no Capture attempt or hardware session exists."
                    ) {
                        scenario = .observationCancelled
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nembra.capture.observation.surface")

            qaControl(
                title: "Present completed observation",
                identifier: "nembra.capture.qa.complete-observation"
            ) {
                scenario = .integrityPending
            }
        }
    }

    private var integrityPendingSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            panel {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CAPTURE SEALED")
                                .font(.caption2.bold())
                                .tracking(1.3)
                                .foregroundStyle(.cyan)
                            Text("Artifact preparation needed")
                                .font(.title2.bold())
                        }
                    }
                    Text("Synthetic observation completion is being presented. No artifact bytes exist, so COMPLETE and Share remain unavailable.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nembra.capture.integrity")

            qaControl(
                title: "Present integrity-verified UI",
                identifier: "nembra.capture.qa.verify-integrity"
            ) {
                scenario = .complete
            }
        }
    }

    private var completeSurface: some View {
        panel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CAPTURE COMPLETE")
                            .font(.caption2.bold())
                            .tracking(1.3)
                            .foregroundStyle(.green)
                            .accessibilityIdentifier("nembra.capture.complete")
                        Text("Ready for analysis")
                            .font(.title.bold())
                    }
                }

                Text("SYNTHETIC UI STATE · NO CAPTURE ARTIFACT")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)

                Text("This checks the integrity-gated COMPLETE layout only. It does not encode, seal, verify, retain, or export bytes.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Integrity presentation verified", systemImage: "checkmark.shield.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Text("Display-only QA digest · SYNTHETIC-NO-ARTIFACT-0001")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("nembra.capture.integrity")
                .accessibilityLabel("Synthetic integrity presentation verified; no artifact exists")

                Button {
                    shareAttemptCount += 1
                    presentedSheet = .share(attempt: shareAttemptCount)
                } label: {
                    Label("Share Capture", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("nembra.capture.share")
                .accessibilityHint("Opens only the disclosed synthetic share-retry presentation. No file or artifact exists.")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Production recovery copy under test")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("If sharing is cancelled or fails, tap Share Capture again. The same verified bytes remain sealed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func stoppedSurface(
        kicker: String,
        title: String,
        message: String,
        identifier: String
    ) -> some View {
        panel {
            VStack(alignment: .leading, spacing: 14) {
                Text(kicker)
                    .font(.caption2.bold())
                    .tracking(1.2)
                    .foregroundStyle(.orange)
                Label(title, systemImage: "exclamationmark.circle")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This terminal presentation cannot confirm a scooter, start observation, or show COMPLETE or Share.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func requirementRow(_ title: String, ready: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            Text(ready ? "Ready" : "Required")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ready ? Color.green : Color.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(ready ? "ready" : "required") in synthetic presentation")
    }

    private func qaControl(
        title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SYNTHETIC QA CONTROL")
                .font(.caption2.bold())
                .tracking(1.1)
                .foregroundStyle(.orange)
            Button(title, action: action)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier(identifier)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        }
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(isCompactHeight ? 16 : 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
    }
}

@MainActor
struct CaptureSimulatorQAInvalidScenarioView: View {
    let rawValue: String

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Label("Synthetic QA launch blocked", systemImage: "xmark.octagon.fill")
                        .font(.title.bold())
                        .foregroundStyle(.orange)
                    Text("The requested scenario is missing or is not allow-listed: \(rawValue)")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Allowed: \(CaptureSimulatorQAScenario.allCases.map(\.rawValue).joined(separator: ", "))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Capture QA")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                CapturePresentationDisclosureBanner(
                    text: CaptureSimulatorQADisclosure.text,
                    accessibilityIdentifier: CaptureSimulatorQADisclosure.rootIdentifier
                )
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nembra.capture.qa.invalid-scenario")
    }
}

@MainActor
private struct CaptureSimulatorQAShareSurrogate: View {
    let attempt: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("SYNTHETIC SHARE SURROGATE")
                    .font(.caption2.bold())
                    .tracking(1.2)
                    .foregroundStyle(.orange)
                Text("Synthetic share attempt \(attempt)")
                    .font(.title.bold())
                Text("This sheet checks cancellation and retry routing only. It has no file, bytes, activity controller, or external destination.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Cancel synthetic share") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("nembra.capture.qa.share-cancel")
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Share QA")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                CapturePresentationDisclosureBanner(
                    text: CaptureSimulatorQADisclosure.text,
                    accessibilityIdentifier: CaptureSimulatorQADisclosure.sheetIdentifier
                )
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nembra.capture.qa.share-surrogate")
    }
}
#endif