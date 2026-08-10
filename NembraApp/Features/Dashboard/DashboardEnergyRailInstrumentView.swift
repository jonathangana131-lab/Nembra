import Dispatch
import NembraCore
import SwiftUI

/// Localized app adapter for the signature Energy Rail.
///
/// Positive propulsion authority enters only through `VehicleStore`'s source-owned
/// `SimulatorPowerEvidenceAvailability`. This view never reads aggregate `powerWatts`,
/// speed chronology, ride mode, a view-mount timestamp, or a render timestamp to mint
/// a power receipt. The package runtime owns accepted chronology and interpolation;
/// this view owns only when SwiftUI asks that projection to render.
@MainActor
struct DashboardEnergyRailInstrumentView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var runtime: PropulsionEnergyRailSimulatorRuntime?
    @State private var transitionWakeTask: Task<Void, Never>?
    @State private var scheduleRevision: UInt64 = 0

    var body: some View {
        _ = scheduleRevision
        let now = DispatchTime.now().uptimeNanoseconds
        let schedule = runtime?.displaySchedule(atUptimeNanoseconds: now)
        let continuousFrames = !reduceMotion && (schedule?.requiresContinuousFrames == true)

        TimelineView(
            .animation(
                minimumInterval: 1.0 / 60.0,
                paused: !continuousFrames
            )
        ) { _ in
            let renderUptime = DispatchTime.now().uptimeNanoseconds
            let visualState = runtime.map {
                NembraEnergyRailVisualState(
                    projection: $0.projection(atUptimeNanoseconds: renderUptime)
                )
            } ?? .unavailable

            NembraEnergyRailView(state: visualState)
                .frame(maxWidth: .infinity)
        }
        .task {
            synchronizeSourceAuthority()
        }
        .onChange(of: vehicle.simulatorPowerEvidenceAvailability) { _, _ in
            synchronizeSourceAuthority()
        }
        .onChange(of: vehicle.hasSimulatorPowerEvidenceSource) { _, _ in
            synchronizeSourceAuthority()
        }
        .onChange(of: reduceMotion) { _, _ in
            scheduleNextPresentationWake()
        }
        .onDisappear {
            transitionWakeTask?.cancel()
            transitionWakeTask = nil
        }
    }

    private func synchronizeSourceAuthority() {
        transitionWakeTask?.cancel()
        transitionWakeTask = nil

        guard vehicle.hasSimulatorPowerEvidenceSource else {
            if var runtime {
                runtime.markUnavailable()
                self.runtime = runtime
            } else {
                runtime = nil
            }
            scheduleRevision &+= 1
            return
        }

        var candidate = runtime
        if candidate == nil {
            candidate = try? PropulsionEnergyRailSimulatorRuntime()
        }
        guard var candidate else {
            runtime = nil
            scheduleRevision &+= 1
            return
        }

        switch vehicle.simulatorPowerEvidenceAvailability {
        case .unavailable:
            candidate.markUnavailable()

        case let .retained(observation):
            _ = candidate.retainSource(
                watts: observation.watts,
                receiptSequenceNumber: observation.receiptSequenceNumber,
                receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                continuityGeneration: observation.continuityGeneration
            )

        case let .live(observation):
            _ = candidate.acceptLiveSource(
                watts: observation.watts,
                receiptSequenceNumber: observation.receiptSequenceNumber,
                receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
                continuityGeneration: observation.continuityGeneration
            )
        }

        runtime = candidate
        scheduleRevision &+= 1
        scheduleNextPresentationWake()
    }

    /// Schedules only package-declared display transitions. Source currentness and
    /// measurement chronology remain unchanged by this wake task.
    private func scheduleNextPresentationWake() {
        transitionWakeTask?.cancel()
        transitionWakeTask = nil

        let now = DispatchTime.now().uptimeNanoseconds
        guard let next = runtime?
            .displaySchedule(atUptimeNanoseconds: now)
            .nextTransitionUptimeNanoseconds,
              next > now else {
            return
        }

        let delay = next - now
        transitionWakeTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            scheduleRevision &+= 1
            scheduleNextPresentationWake()
        }
    }
}

/// Central cockpit composition. Speed keeps its already accepted source/currentness
/// model and local render clock; Energy Rail gets an independent localized render
/// clock driven by source-owned power evidence. Neither render subtree feeds the other.
struct DashboardCenterInstrumentView: View {
    let modePersonality: DashboardModePersonality

    var body: some View {
        VStack(spacing: -4) {
            DashboardSpeedInstrumentView(modePersonality: modePersonality)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(3)

            DashboardEnergyRailInstrumentView()
                .frame(maxWidth: .infinity)
                .layoutPriority(2)
        }
    }
}
