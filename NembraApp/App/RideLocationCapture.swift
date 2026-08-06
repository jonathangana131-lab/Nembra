import CoreLocation
import Dispatch
import Foundation

/// Transport/authorization state from Apple's location stream. These are not
/// route-quality verdicts; `RideLocationQualityScreen` remains the authority for
/// whether a concrete coordinate can become durable ride evidence.
enum RideLocationSourceIssue: Equatable, Sendable {
    case authorizationRequestInProgress
    case authorizationDenied
    case authorizationDeniedGlobally
    case authorizationRestricted
    case accuracyLimited
    case insufficientlyInUse
    case locationUnavailable
    case serviceSessionRequired
    case invalidLocation
    case streamFailed
}

struct RideLocationSourceEvent: Equatable, Sendable {
    let sample: RideLocationSample?
    let issue: RideLocationSourceIssue?
    let isStationary: Bool

    init(
        sample: RideLocationSample?,
        issue: RideLocationSourceIssue?,
        isStationary: Bool
    ) {
        self.sample = sample
        self.issue = issue
        self.isStationary = isStationary
    }
}

/// Injectable phone-location boundary. Tests and Simulator fixtures use their
/// own implementation; production Core Location stays behind the same event
/// stream so route/distance logic never imports CoreLocation types.
protocol RideLocationSource: Sendable {
    func events() async -> AsyncStream<RideLocationSourceEvent>
    func start() async
    func stop() async
}

/// Foreground Core Location adapter for a scooter ride.
///
/// Apple explicitly includes scooters in `.otherNavigation`. Nembra starts this
/// source only when a ride-lifecycle coordinator asks for location evidence; it
/// does not run high-accuracy location continuously at ordinary app launch.
/// Background continuation is deliberately not claimed here: that requires the
/// separate SwiftUI lifecycle/background-session gate and physical-device QA.
actor CoreLocationRideLocationSource: RideLocationSource {
    private var continuation: AsyncStream<RideLocationSourceEvent>.Continuation?
    private var updatesTask: Task<Void, Never>?
    private var serviceSession: CLServiceSession?

    func events() -> AsyncStream<RideLocationSourceEvent> {
        let pair = AsyncStream<RideLocationSourceEvent>.makeStream()
        continuation?.finish()
        continuation = pair.continuation
        return pair.stream
    }

    func start() {
        guard updatesTask == nil else { return }

        // Holding the service session states the authorization goal explicitly
        // for the lifetime of this ride-location source. The project already has
        // NSLocationWhenInUseUsageDescription; this call is made only from a
        // user-visible ride/location flow, never as a surprise at cold launch.
        serviceSession = CLServiceSession.session(authorization: .whenInUse)
        updatesTask = Task { [weak self] in
            await self?.consumeLiveUpdates()
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        serviceSession = nil
        continuation?.finish()
        continuation = nil
    }

    private func consumeLiveUpdates() async {
        do {
            for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                guard !Task.isCancelled else { break }
                continuation?.yield(makeEvent(from: update))
            }
        } catch is CancellationError {
            // Normal stop path.
        } catch {
            continuation?.yield(
                RideLocationSourceEvent(
                    sample: nil,
                    issue: .streamFailed,
                    isStationary: false
                )
            )
        }
    }

    private func makeEvent(from update: CLLocationUpdate) -> RideLocationSourceEvent {
        let issue = issue(from: update)
        guard let location = update.location else {
            return RideLocationSourceEvent(
                sample: nil,
                issue: issue ?? .locationUnavailable,
                isStationary: update.isStationary
            )
        }

        do {
            let sample = try RideLocationSample(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                sourceMeasurementDate: location.timestamp,
                receivedAtDate: .now,
                receivedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                horizontalAccuracyMeters: location.horizontalAccuracy,
                isAccuracyLimited: update.accuracyLimited,
                isSimulatedBySoftware: location.sourceInformation?.isSimulatedBySoftware ?? false
            )
            return RideLocationSourceEvent(
                sample: sample,
                issue: issue,
                isStationary: update.isStationary
            )
        } catch {
            return RideLocationSourceEvent(
                sample: nil,
                issue: .invalidLocation,
                isStationary: update.isStationary
            )
        }
    }

    private func issue(from update: CLLocationUpdate) -> RideLocationSourceIssue? {
        if update.authorizationDeniedGlobally { return .authorizationDeniedGlobally }
        if update.authorizationRestricted { return .authorizationRestricted }
        if update.authorizationDenied { return .authorizationDenied }
        if update.serviceSessionRequired { return .serviceSessionRequired }
        if update.authorizationRequestInProgress { return .authorizationRequestInProgress }
        if update.insufficientlyInUse { return .insufficientlyInUse }
        if update.locationUnavailable { return .locationUnavailable }
        if update.accuracyLimited { return .accuracyLimited }
        return nil
    }
}
