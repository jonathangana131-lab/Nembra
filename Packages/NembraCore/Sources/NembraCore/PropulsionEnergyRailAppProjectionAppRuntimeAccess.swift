/// Public negative-only lowering seam for the app-local Simulator Energy Rail runtime.
///
/// The canonical zero-argument implementation remains package-internal. This overload
/// exists only so a runtime directly compiled into the app can demote an already-sealed
/// package projection without gaining any constructor for accepted watts, receipts, or
/// physical authority. The defaulted marker preserves the zero-argument call shape for
/// external clients while package code continues to prefer the exact internal overload.
public extension PropulsionEnergyRailAppProjection {
    func retainedWithoutNewMeasurement(
        _ appRuntimeNegativeAuthorityAccess: Void = ()
    ) -> PropulsionEnergyRailAppProjection {
        retainedWithoutNewMeasurement()
    }
}
