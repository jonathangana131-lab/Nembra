import Foundation

/// Reconciles route geometry with the independent per-session outcome ledger.
///
/// This type deliberately does not own ride history/checkpoint state. AppRuntime
/// calls it before a completed checkpoint can be acknowledged and also performs
/// best-effort startup repair for durable `storageFailed` / `unknown` outcomes
/// after history has already committed. Route repair therefore remains additive:
/// it can improve map truth later without rewriting completed ride evidence.
struct RideRouteOutcomeReconciler: Sendable {
    private let outcomeStore: AtomicRideRouteOutcomeStore
    private let draftFinalizer: RideRouteDraftFinalizer?

    init(
        outcomeStore: AtomicRideRouteOutcomeStore,
        draftFinalizer: RideRouteDraftFinalizer?
    ) {
        self.outcomeStore = outcomeStore
        self.draftFinalizer = draftFinalizer
    }

    func persistCaptureSummary(_ summary: RideLocationCaptureSummary) async throws {
        if !summary.routePersistenceFailed,
           let manifest = summary.routeManifest {
            try await commit(
                sessionID: summary.sessionID,
                state: manifest.pointCount > 0 ? .recorded : .noRecordedGeometry,
                acceptedPointCount: summary.acceptedPointCount
            )
            return
        }

        // A normal manifest failure can leave verified immutable chunks. Salvage
        // them immediately before history acknowledgment if possible. If salvage
        // is unavailable or fails, preserve explicit storage failure rather than
        // collapsing it into an ordinary no-route state.
        if let draftFinalizer {
            do {
                if let manifest = try await draftFinalizer.finalizePartialDraftIfNeeded(
                    sessionID: summary.sessionID
                ), manifest.pointCount > 0 {
                    try await commit(
                        sessionID: summary.sessionID,
                        state: .recorded,
                        acceptedPointCount: summary.acceptedPointCount
                    )
                    return
                }
            } catch {
                // The failure ledger below remains the repair obligation.
            }
        }

        try await commit(
            sessionID: summary.sessionID,
            state: .storageFailed,
            acceptedPointCount: summary.acceptedPointCount
        )
    }

    /// Reconcile one durable session without inventing evidence across a process
    /// boundary. In particular, route manifest point count is never substituted
    /// for the application's admitted-point count; if that count was not already
    /// known in the outcome ledger it stays unknown (`nil`).
    func reconcile(sessionID: UUID) async throws {
        let existing = try await outcomeStore.record(sessionID: sessionID)

        switch existing?.state {
        case .recorded, .noRecordedGeometry:
            return
        case .storageFailed, .unknown, .none:
            break
        }

        if let draftFinalizer {
            do {
                if let manifest = try await draftFinalizer.finalizePartialDraftIfNeeded(
                    sessionID: sessionID
                ) {
                    if manifest.pointCount > 0 {
                        try await commit(
                            sessionID: sessionID,
                            state: .recorded,
                            acceptedPointCount: existing?.acceptedPointCount
                        )
                        return
                    }

                    // A verified zero-point manifest can establish no geometry
                    // only when there was not already an explicit storage failure.
                    // `storageFailed` remains conservative rather than being
                    // rewritten as no-route after a later empty recovery read.
                    if existing?.state != .storageFailed {
                        try await commit(
                            sessionID: sessionID,
                            state: .noRecordedGeometry,
                            acceptedPointCount: existing?.acceptedPointCount
                        )
                    }
                    return
                }
            } catch {
                try await commit(
                    sessionID: sessionID,
                    state: .storageFailed,
                    acceptedPointCount: existing?.acceptedPointCount
                )
                return
            }

            // Existing nonterminal truth stays nonterminal when there is nothing
            // salvageable. Legacy pending checkpoints with neither geometry nor
            // outcome are `unknown`; a process boundary does not prove no route.
            if existing != nil { return }
            try await commit(
                sessionID: sessionID,
                state: .unknown,
                acceptedPointCount: nil
            )
            return
        }

        // If the optional route database cannot open, the inability to inspect
        // geometry is itself storage failure. Preserve any previously known app
        // point count but do not infer one from unavailable route data.
        try await commit(
            sessionID: sessionID,
            state: .storageFailed,
            acceptedPointCount: existing?.acceptedPointCount
        )
    }

    /// Best-effort startup repair that remains useful even after the completed
    /// ride checkpoint has already been acknowledged. Invalid/corrupt outcome
    /// payloads are not trusted or rewritten here; their presentation path will
    /// continue to fail closed for the affected session.
    func repairOutstandingOutcomes() async {
        guard let sessionIDs = try? await outcomeStore.sessionIDs() else { return }
        for sessionID in sessionIDs {
            guard let record = try? await outcomeStore.record(sessionID: sessionID) else {
                continue
            }
            switch record.state {
            case .storageFailed, .unknown:
                try? await reconcile(sessionID: sessionID)
            case .recorded, .noRecordedGeometry:
                continue
            }
        }
    }

    private func commit(
        sessionID: UUID,
        state: RideRouteOutcomeState,
        acceptedPointCount: Int?
    ) async throws {
        let record = try RideRouteOutcomeRecord(
            sessionID: sessionID,
            state: state,
            acceptedPointCount: acceptedPointCount
        )
        _ = try await outcomeStore.commit(record)
    }
}
