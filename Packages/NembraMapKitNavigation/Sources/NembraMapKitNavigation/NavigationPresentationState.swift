import NembraCore

public enum NavigationPlanningPresentation: Equatable, Sendable {
    case idle
    case requesting(NavigationRoutePlanRequest)
    case alternativesAvailable(NavigationRoutePlanRequest)
    case failed(request: NavigationRoutePlanRequest, reason: NavigationRoutePlanFailure)
}

public struct NavigationRouteOptionPresentation: Equatable, Sendable {
    public let selectionID: NavigationRouteSelectionID
    public let index: Int
    public let name: String
    public let distanceMeters: Double
    public let expectedTravelTimeSeconds: Double
    public let hasHighways: Bool
    public let hasTolls: Bool
    public let advisoryNotices: [String]
    public let provider: NavigationRouteProvider
    public let requestedTransportMode: NavigationRouteTransportMode
    public let returnedTransportMode: NavigationRouteTransportMode
    public let isSelected: Bool
}

public enum NavigationGuidancePresentation: Equatable, Sendable {
    case inactive
    case unavailable(
        routeName: String,
        reason: NavigationGuidanceUnavailableReason
    )
    case active(
        routeName: String,
        currentInstruction: String,
        currentNotice: String?,
        nextInstruction: String?,
        nextNotice: String?,
        distanceRemainingOnStepMeters: Double,
        distanceRemainingOnRouteMeters: Double
    )
}

public struct NavigationPresentationSnapshot: Equatable, Sendable {
    public let planning: NavigationPlanningPresentation
    public let routeOptions: [NavigationRouteOptionPresentation]
    public let selectedRouteName: String?
    public let guidance: NavigationGuidancePresentation
}

/// Pure semantic projection for future SwiftUI surfaces.
///
/// This layer preserves provider strings/facts and unit-neutral numeric values.
/// It deliberately does not infer maneuver icons from localized text, choose a
/// preferred route, format measurement units, or turn navigation estimates into
/// ride telemetry.
public enum NavigationPresentationProjector {
    public static func snapshot(
        from experience: NavigationExperienceSnapshot
    ) -> NavigationPresentationSnapshot {
        let planning: NavigationPlanningPresentation
        let availableToken: NavigationRouteRequestToken?
        switch experience.planningState {
        case .idle:
            planning = .idle
            availableToken = nil
        case let .requesting(_, request):
            planning = .requesting(request)
            availableToken = nil
        case let .available(token, request, _):
            planning = .alternativesAvailable(request)
            availableToken = token
        case let .failed(_, request, reason):
            planning = .failed(request: request, reason: reason)
            availableToken = nil
        }

        let options: [NavigationRouteOptionPresentation]
        if let selection = experience.routeSelection,
           let availableToken {
            options = selection.routes.enumerated().map { index, route in
                NavigationRouteOptionPresentation(
                    selectionID: NavigationRouteSelectionID(
                        requestToken: availableToken,
                        index: index
                    ),
                    index: index,
                    name: route.name,
                    distanceMeters: route.distanceMeters,
                    expectedTravelTimeSeconds: route.expectedTravelTimeSeconds,
                    hasHighways: route.hasHighways,
                    hasTolls: route.hasTolls,
                    advisoryNotices: route.advisoryNotices,
                    provider: route.provenance.provider,
                    requestedTransportMode: route.provenance.requestedTransportMode,
                    returnedTransportMode: route.provenance.returnedTransportMode,
                    isSelected: selection.selectedIndex == index
                )
            }
        } else {
            options = []
        }

        let guidance: NavigationGuidancePresentation
        switch experience.guidanceState {
        case .idle:
            guidance = .inactive
        case let .unavailable(_, route, reason):
            guidance = .unavailable(routeName: route.name, reason: reason)
        case let .active(_, route, progress):
            guidance = .active(
                routeName: route.name,
                currentInstruction: progress.currentStep.instructions,
                currentNotice: progress.currentStep.notice,
                nextInstruction: progress.nextStep?.instructions,
                nextNotice: progress.nextStep?.notice,
                distanceRemainingOnStepMeters: progress.distanceRemainingOnStepMeters,
                distanceRemainingOnRouteMeters: progress.distanceRemainingOnRouteMeters
            )
        }

        return NavigationPresentationSnapshot(
            planning: planning,
            routeOptions: options,
            selectedRouteName: experience.selectedRoute?.name,
            guidance: guidance
        )
    }
}
