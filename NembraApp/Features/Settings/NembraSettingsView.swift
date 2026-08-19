import CoreBluetooth
import CoreLocation
import SwiftUI
import UIKit

enum NembraPreferenceKey {
    static let units = "nembra.preference.units.v1"
    static let appearance = "nembra.preference.appearance.v1"
    static let rideNotifications = "nembra.preference.ride-notifications.v1"
    static let haptics = "nembra.preference.haptics.v1"
}

enum NembraUnitsPreference: String, CaseIterable, Identifiable {
    case system
    case miles
    case metric

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .miles: "Miles · mph"
        case .metric: "Kilometers · km/h"
        }
    }
}

enum NembraAppearancePreference: String, CaseIterable, Identifiable {
    case nembraDark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nembraDark: "Nembra Dark"
        case .system: "System"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .nembraDark: .dark
        case .system: nil
        }
    }
}

/// Native-quiet Settings surface from the selected Nembra 1.0 direction.
/// Rows expose only implemented preferences or truthful capability/status
/// detail; unavailable automatic-capture prerequisites are not presented as on.
struct NembraSettingsView: View {
    @Environment(AutomaticCaptureReadinessStore.self) private var automaticCapture
    @Environment(VehicleStore.self) private var vehicle
    @Environment(RideHistoryPresentationStore.self) private var history
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(NembraPreferenceKey.units) private var unitsRaw = NembraUnitsPreference.system.rawValue
    @AppStorage(NembraPreferenceKey.appearance) private var appearanceRaw = NembraAppearancePreference.nembraDark.rawValue
    @AppStorage(NembraPreferenceKey.rideNotifications) private var rideNotifications = true
    @AppStorage(NembraPreferenceKey.haptics) private var haptics = true

    @State private var permissionRevision = 0

    var body: some View {
        List {
            identitySection
            ridePreferencesSection
            dataAndPrivacySection
            aboutSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(NembraColor.baseBlack)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .tint(NembraColor.gold)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                appearanceMenu
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { permissionRevision &+= 1 }
        }
        .accessibilityIdentifier("settings.surface")
    }

    private var identitySection: some View {
        Section {
            NavigationLink {
                VehicleControlsView()
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [NembraColor.gold, NembraColor.deepGold],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("N")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 62, height: 62)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nembra")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(NembraColor.primaryText)

                        HStack(spacing: 7) {
                            Circle()
                                .fill(connectionColor)
                                .frame(width: 7, height: 7)
                                .accessibilityHidden(true)
                            Text(identitySubtitle)
                                .font(.subheadline)
                                .foregroundStyle(NembraColor.secondaryText)
                                .lineLimit(2)
                        }

                        if vehicle.profile == .simulatorQA {
                            Text("SIMULATOR QA · SYNTHETIC EVIDENCE")
                                .font(.caption2.weight(.semibold))
                                .tracking(0.7)
                                .foregroundStyle(NembraColor.secondaryText.opacity(0.82))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .accessibilityIdentifier("settings.identity")
        }
        .listRowInsets(.init(top: 8, leading: 24, bottom: 12, trailing: 20))
        .listRowBackground(NembraColor.baseBlack)
        .listRowSeparatorTint(NembraColor.quietLine)
    }

    private var ridePreferencesSection: some View {
        Section {
            Picker(selection: unitsBinding) {
                ForEach(NembraUnitsPreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            } label: {
                settingsLabel(
                    "Units",
                    subtitle: "Distance and speed",
                    systemImage: "ruler",
                    iconIsAccented: true
                )
            }
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("settings.units")

            Picker(selection: appearanceBinding) {
                ForEach(NembraAppearancePreference.allCases) { preference in
                    Text(preference.title).tag(preference)
                }
            } label: {
                settingsLabel(
                    "Appearance",
                    subtitle: "Match Nembra or system",
                    systemImage: "moon"
                )
            }
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("settings.appearance")

            NavigationLink {
                NembraRideNotificationsView(isEnabled: $rideNotifications)
            } label: {
                settingsLabel(
                    "Ride notifications",
                    subtitle: "Connection, ride, and battery alerts",
                    systemImage: "bell"
                )
            }
            .accessibilityIdentifier("settings.ride-notifications")

            Toggle(isOn: $haptics) {
                settingsLabel(
                    "Haptics",
                    subtitle: "Confirmed controls and meaningful warnings",
                    systemImage: "waveform"
                )
            }
            .accessibilityIdentifier("settings.haptics")

            NavigationLink {
                AutomaticCaptureSettingsView()
            } label: {
                settingsLabel(
                    "Automatic ride capture",
                    subtitle: automaticCapture.settingsRowSubtitle,
                    systemImage: "record.circle"
                )
            }
            .accessibilityIdentifier("settings.automatic-capture")
        } header: {
            sectionHeader("Ride preferences")
        }
        .listRowBackground(NembraColor.baseBlack)
        .listRowSeparatorTint(NembraColor.quietLine)
        .listRowInsets(.init(top: 7, leading: 24, bottom: 7, trailing: 20))
    }

    private var dataAndPrivacySection: some View {
        Section {
            NavigationLink {
                NembraPermissionsView()
            } label: {
                settingsLabel(
                    "Permissions",
                    subtitle: "Bluetooth and location",
                    systemImage: "shield",
                    trailingValue: permissionSummary
                )
            }
            .accessibilityIdentifier("settings.permissions")

            if let exportText {
                ShareLink(item: exportText) {
                    settingsLabel(
                        "Export ride data",
                        subtitle: "JSON · \(history.records.count) saved rides",
                        systemImage: "arrow.down.to.line"
                    )
                }
                .accessibilityIdentifier("settings.export-rides")
            } else {
                settingsLabel(
                    "Export ride data",
                    subtitle: history.status == .loading ? "Loading saved rides" : "No saved rides to export",
                    systemImage: "arrow.down.to.line"
                )
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.export-rides-unavailable")
            }
        } header: {
            sectionHeader("Data & privacy")
        }
        .listRowBackground(NembraColor.baseBlack)
        .listRowSeparatorTint(NembraColor.quietLine)
        .listRowInsets(.init(top: 7, leading: 24, bottom: 7, trailing: 20))
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                NembraAboutView()
            } label: {
                settingsLabel(
                    "About Nembra",
                    subtitle: "Version, privacy, and acknowledgements",
                    systemImage: "info.circle"
                )
            }
            .accessibilityIdentifier("settings.about")
        }
        .listRowBackground(NembraColor.baseBlack)
        .listRowSeparatorTint(NembraColor.quietLine)
        .listRowInsets(.init(top: 7, leading: 24, bottom: 7, trailing: 20))
    }

    private func settingsLabel(
        _ title: String,
        subtitle: String,
        systemImage: String,
        trailingValue: String? = nil,
        iconIsAccented: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(iconIsAccented ? NembraColor.gold : NembraColor.secondaryText)
                .frame(width: 44, height: 44)
                .background(
                    iconIsAccented
                        ? NembraColor.deepGold.opacity(0.20)
                        : NembraColor.quietSurface,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(NembraColor.primaryText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(NembraColor.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let trailingValue {
                Text(trailingValue)
                    .font(.subheadline)
                    .foregroundStyle(NembraColor.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .frame(minHeight: 58)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .tracking(2.1)
            .foregroundStyle(NembraColor.secondaryText)
            .textCase(nil)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private var appearanceMenu: some View {
        Menu {
            ForEach(NembraAppearancePreference.allCases) { preference in
                Button {
                    appearanceRaw = preference.rawValue
                } label: {
                    if appearanceBinding.wrappedValue == preference {
                        Label(preference.title, systemImage: "checkmark")
                    } else {
                        Text(preference.title)
                    }
                }
            }
        } label: {
            Label("Appearance", systemImage: "sun.max")
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Appearance")
        .accessibilityHint("Choose Nembra Dark or follow the system appearance.")
        .accessibilityIdentifier("settings.appearance-menu")
    }

    private var unitsBinding: Binding<NembraUnitsPreference> {
        Binding(
            get: { NembraUnitsPreference(rawValue: unitsRaw) ?? .system },
            set: { unitsRaw = $0.rawValue }
        )
    }

    private var appearanceBinding: Binding<NembraAppearancePreference> {
        Binding(
            get: { NembraAppearancePreference(rawValue: appearanceRaw) ?? .nembraDark },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    private var permissionSummary: String {
        _ = permissionRevision
        let allowedCount = [isBluetoothAllowed, isLocationAllowed].filter { $0 }.count
        switch allowedCount {
        case 2: return "2 allowed"
        case 1: return "1 allowed"
        default:
            return bluetoothAuthorizationText == "not requested" && locationAuthorizationText == "not requested"
                ? "Not requested"
                : "Needs attention"
        }
    }

    private var isBluetoothAllowed: Bool {
        CBCentralManager.authorization == .allowedAlways
    }

    private var isLocationAllowed: Bool {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: true
        default: false
        }
    }

    private var bluetoothAuthorizationText: String {
        switch CBCentralManager.authorization {
        case .allowedAlways: "allowed"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not requested"
        @unknown default: "unknown"
        }
    }

    private var locationAuthorizationText: String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways: "always"
        case .authorizedWhenInUse: "while using"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not requested"
        @unknown default: "unknown"
        }
    }

    private var identitySubtitle: String {
        "\(displayVehicleName) · \(connectionText)"
    }

    private var displayVehicleName: String {
        vehicle.profile == .simulatorQA
            ? VehicleProfile.aovoproES80.identity.displayName
            : vehicle.profile.identity.displayName
    }

    private var connectionColor: Color {
        switch vehicle.state.connection {
        case .connected: .green
        case .connecting, .reconnecting: NembraColor.gold
        case .disconnected: NembraColor.secondaryText
        }
    }

    private var connectionText: String {
        switch vehicle.state.connection {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .reconnecting: "Reconnecting"
        case .disconnected: "Offline"
        }
    }

    private var exportText: String? {
        guard !history.records.isEmpty,
              let data = try? JSONEncoder().encode(history.records),
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }
}

private struct NembraRideNotificationsView: View {
    @Binding var isEnabled: Bool

    var body: some View {
        List {
            Section {
                Toggle("Ride notifications", isOn: $isEnabled)
                    .accessibilityIdentifier("settings.ride-notifications.enabled")
            } footer: {
                Text("Nembra can surface connection, ride, and battery alerts when notifications are allowed in iOS Settings. This preference does not bypass system permission.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(NembraColor.baseBlack)
        .navigationTitle("Ride notifications")
        .navigationBarTitleDisplayMode(.inline)
        .tint(NembraColor.gold)
        .accessibilityIdentifier("settings.ride-notifications.detail")
    }
}

private struct AutomaticCaptureSettingsView: View {
    @Environment(AutomaticCaptureReadinessStore.self) private var automaticCapture
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var capture = automaticCapture

        List {
            Section("Current status") {
                LabeledContent("Ride telemetry", value: automaticCapture.telemetryStatusText)
                LabeledContent("Route & Explore", value: automaticCapture.roadCoverageStatusText)
                LabeledContent("App", value: automaticCapture.facts.sceneState.title)
                Text("Ready means best effort under public iOS scheduling and lifecycle rules, never an always-running guarantee.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Your preference") {
                Toggle("Allow automatic capture when ready", isOn: $capture.isAutomaticCaptureEnabled)
                    .accessibilityIdentifier("settings.automatic-capture.enabled")
                Text("This records your intent only. Turning it on cannot bypass missing accessory authority, permissions, restoration, or storage evidence.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("One-time setup") {
                LabeledContent("Scooter descriptor", value: automaticCapture.accessorySetupText)
                LabeledContent("iOS accessory approval", value: accessoryAuthorizationText)
                LabeledContent("Background restoration", value: automaticCapture.restorationText)
                Text("Nembra will not install AccessorySetupKit discovery identifiers or a background Bluetooth owner until Capture proves the exact physical ES80 descriptor.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Bluetooth", value: automaticCapture.bluetoothAuthorizationText)
                LabeledContent("Location", value: automaticCapture.locationAuthorizationText)
                Text("Bluetooth is required for ride telemetry. Always Location plus a verified ride-scoped background session are required for automatic route and Explore coverage.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if automaticCapture.shouldOfferSystemSettings {
                    Button("Open iOS Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                    .accessibilityIdentifier("settings.automatic-capture.open-system-settings")
                }
            }

            if !automaticCapture.blockers.isEmpty {
                Section("Setup blockers") {
                    ForEach(automaticCapture.blockers) { blocker in
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(blocker.title)
                                    .font(.body.weight(.semibold))
                                Text(blocker.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(NembraColor.gold)
                        }
                    }
                }
            }

            Section("iOS lifecycle limits") {
                LabeledContent("First unlock after restart", value: automaticCapture.firstUnlockText)
                Text(automaticCapture.forceQuitTruthText)
                Text("After an iPhone restart, protected ride storage remains blocked until the first unlock. Nembra reports that condition instead of dropping or inventing evidence.")
            }

            Section {
                Button {
                    automaticCapture.refreshAndRearm()
                } label: {
                    Label("Refresh status", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("settings.automatic-capture.refresh")

                if let message = automaticCapture.lastActionMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.automatic-capture.refresh-result")
                }
            }
        }
        .navigationTitle("Automatic capture")
        .navigationBarTitleDisplayMode(.inline)
        .tint(NembraColor.gold)
        .task { automaticCapture.refresh() }
        .accessibilityIdentifier("settings.automatic-capture.detail")
    }

    private var accessoryAuthorizationText: String {
        switch automaticCapture.facts.accessorySetupAuthorization {
        case .authorized: "Authorized"
        case .denied: "Denied"
        case .removed: "Removed"
        case .notDetermined: "Not approved"
        case .notEvaluated: "Not available yet"
        case .frameworkUnavailable: "Unavailable"
        }
    }
}

private struct NembraPermissionsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section("Bluetooth") {
                LabeledContent("Nembra access", value: bluetoothText)
                Text("Bluetooth is required to reconnect to the authorized scooter and receive accepted telemetry.")
            }
            Section("Location") {
                LabeledContent("Nembra access", value: locationText)
                Text("Location records accepted ride routes and Explore coverage. Missing or interrupted location remains an explicit route gap and never becomes invented distance.")
            }
            Section {
                Button("Open iOS Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            }
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.permissions.detail")
    }

    private var bluetoothText: String {
        switch CBCentralManager.authorization {
        case .allowedAlways: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private var locationText: String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }
}

private struct NembraAboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: versionText)
                LabeledContent("Data storage", value: "On this iPhone")
            }
            Section("Product truth") {
                Text("Nembra distinguishes live, retained, partial, unavailable, and conflicting evidence. It does not infer scooter facts or road coverage from display interpolation.")
            }
        }
        .navigationTitle("About Nembra")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.about.detail")
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (version?, build?): "\(version) (\(build))"
        case let (version?, nil): version
        case let (nil, build?): build
        case (nil, nil): "Unavailable"
        }
    }
}
