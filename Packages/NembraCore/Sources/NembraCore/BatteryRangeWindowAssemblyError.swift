#if SWIFT_PACKAGE
/// Fail-closed errors for assembling one ephemeral learned-range distance span.
///
/// These errors describe software evidence-shape failures only. They do not
/// classify physical scooter distance, battery behavior, or protocol semantics.
enum BatteryRangeWindowAssemblyError: Error, Equatable, Sendable {
    case invalidDistanceDelta
    case distanceOverflow
}
#endif
