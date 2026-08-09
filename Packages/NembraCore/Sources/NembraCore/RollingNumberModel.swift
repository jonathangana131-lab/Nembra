import Foundation

public enum RollingNumberError: Error, Equatable, Sendable {
    case nonFiniteValue
    case negativeValue
    case invalidLayout
    case exceedsLayoutCapacity
}

public enum RollingDigitDirection: String, Equatable, Codable, Sendable {
    case upward
    case downward
    case stationary
}

public enum RollingDigitVisibilityChange: String, Equatable, Codable, Sendable {
    case unchanged
    case appears
    case disappears
}

/// A fixed-width numeric layout for rolling instrumentation.
///
/// Integer slots are always reserved so the rendered width never changes. A
/// leading slot can remain visually hidden while still occupying layout space.
/// Fractional slots are always visible so decimal precision stays stable.
public struct RollingNumberLayout: Equatable, Sendable {
    public let integerDigits: Int
    public let fractionDigits: Int

    public init(integerDigits: Int, fractionDigits: Int = 0) throws {
        guard integerDigits > 0, fractionDigits >= 0 else {
            throw RollingNumberError.invalidLayout
        }
        guard integerDigits + fractionDigits <= 15 else {
            throw RollingNumberError.invalidLayout
        }
        self.integerDigits = integerDigits
        self.fractionDigits = fractionDigits
    }

    public var totalDigitSlots: Int {
        integerDigits + fractionDigits
    }
}

public struct RollingDigitSnapshot: Equatable, Sendable {
    public let digit: Int
    public let isVisible: Bool

    /// Output evidence produced only by `RollingNumberModel`. Keeping construction
    /// file-private prevents callers from manufacturing impossible digit states or
    /// triggering the producer's internal invariant as a public precondition trap.
    fileprivate init(digit: Int, isVisible: Bool) {
        precondition((0...9).contains(digit))
        self.digit = digit
        self.isVisible = isVisible
    }
}

/// Digits are ordered from most-significant integer slot through the least-
/// significant fractional slot. Hidden leading integer digits retain a zero
/// placeholder so geometry can remain fixed without showing leading zeroes.
public struct RollingNumberSnapshot: Equatable, Sendable {
    public let scaledValue: UInt64
    public let layout: RollingNumberLayout
    public let digits: [RollingDigitSnapshot]

    /// Model output only. An explicit file-private initializer prevents the
    /// direct-app build from gaining a synthesized same-module construction seam.
    fileprivate init(
        scaledValue: UInt64,
        layout: RollingNumberLayout,
        digits: [RollingDigitSnapshot]
    ) {
        precondition(digits.count == layout.totalDigitSlots)
        self.scaledValue = scaledValue
        self.layout = layout
        self.digits = digits
    }

    public var integerDigits: ArraySlice<RollingDigitSnapshot> {
        digits.prefix(layout.integerDigits)
    }

    public var fractionalDigits: ArraySlice<RollingDigitSnapshot> {
        digits.suffix(layout.fractionDigits)
    }
}

public struct RollingDigitTransition: Equatable, Sendable {
    public let slotIndex: Int
    public let fromDigit: Int
    public let toDigit: Int
    public let direction: RollingDigitDirection
    public let rollSteps: Int
    public let visibilityChange: RollingDigitVisibilityChange
    public let startsVisible: Bool
    public let endsVisible: Bool

    /// Transition facts are emitted only by `RollingNumberModel`; app/UI code
    /// consumes them read-only instead of fabricating inconsistent slot plans.
    fileprivate init(
        slotIndex: Int,
        fromDigit: Int,
        toDigit: Int,
        direction: RollingDigitDirection,
        rollSteps: Int,
        visibilityChange: RollingDigitVisibilityChange,
        startsVisible: Bool,
        endsVisible: Bool
    ) {
        self.slotIndex = slotIndex
        self.fromDigit = fromDigit
        self.toDigit = toDigit
        self.direction = direction
        self.rollSteps = rollSteps
        self.visibilityChange = visibilityChange
        self.startsVisible = startsVisible
        self.endsVisible = endsVisible
    }

    public var changesDigit: Bool {
        fromDigit != toDigit
    }
}

/// A transition plan between two *display values*. It contains no timing and no
/// sensor semantics. SwiftUI is free to animate the plan, but this object can
/// never be mistaken for raw vehicle telemetry.
public struct RollingNumberTransitionPlan: Equatable, Sendable {
    public let from: RollingNumberSnapshot
    public let to: RollingNumberSnapshot
    public let direction: RollingDigitDirection
    public let slots: [RollingDigitTransition]

    /// Complete plans are model outputs; keeping construction in this file
    /// prevents direct-app consumers from minting inconsistent presentation facts.
    fileprivate init(
        from: RollingNumberSnapshot,
        to: RollingNumberSnapshot,
        direction: RollingDigitDirection,
        slots: [RollingDigitTransition]
    ) {
        self.from = from
        self.to = to
        self.direction = direction
        self.slots = slots
    }

    public var isStationary: Bool {
        direction == .stationary
    }
}

public struct RollingNumberModel: Sendable {
    public let layout: RollingNumberLayout

    private let scale: UInt64
    private let maximumScaledValue: UInt64

    public init(layout: RollingNumberLayout) throws {
        self.layout = layout
        self.scale = try Self.powerOfTen(layout.fractionDigits)
        self.maximumScaledValue = try Self.powerOfTen(layout.totalDigitSlots) - 1
    }

    public func snapshot(for value: Double) throws -> RollingNumberSnapshot {
        guard value.isFinite else {
            throw RollingNumberError.nonFiniteValue
        }
        guard value >= 0 else {
            throw RollingNumberError.negativeValue
        }

        let scaledDouble = (value * Double(scale)).rounded(.toNearestOrAwayFromZero)
        guard scaledDouble.isFinite,
              scaledDouble >= 0,
              scaledDouble <= Double(maximumScaledValue) else {
            throw RollingNumberError.exceedsLayoutCapacity
        }

        let scaledValue = UInt64(scaledDouble)
        let integerValue = scaledValue / scale
        let visibleIntegerCount = max(1, Self.decimalDigitCount(integerValue))
        let firstVisibleIntegerIndex = layout.integerDigits - visibleIntegerCount

        // Build the fixed-slot snapshot directly. The prior implementation first
        // accumulated reversed raw digits and then mapped them into a second
        // snapshot array. This keeps the 60 Hz presentation path to one bounded
        // digit buffer without changing quantization, visibility, or telemetry truth.
        var snapshots = Array(
            repeating: RollingDigitSnapshot(digit: 0, isVisible: false),
            count: layout.totalDigitSlots
        )
        var working = scaledValue
        for index in stride(from: layout.totalDigitSlots - 1, through: 0, by: -1) {
            let digit = Int(working % 10)
            working /= 10
            let isInteger = index < layout.integerDigits
            let visible = isInteger ? index >= firstVisibleIntegerIndex : true
            snapshots[index] = RollingDigitSnapshot(digit: digit, isVisible: visible)
        }

        return RollingNumberSnapshot(
            scaledValue: scaledValue,
            layout: layout,
            digits: snapshots
        )
    }

    public func transition(from oldValue: Double, to newValue: Double) throws -> RollingNumberTransitionPlan {
        try transition(from: snapshot(for: oldValue), to: snapshot(for: newValue))
    }

    public func transition(
        from oldSnapshot: RollingNumberSnapshot,
        to newSnapshot: RollingNumberSnapshot
    ) throws -> RollingNumberTransitionPlan {
        guard oldSnapshot.layout == layout, newSnapshot.layout == layout else {
            throw RollingNumberError.invalidLayout
        }

        let direction: RollingDigitDirection
        if newSnapshot.scaledValue > oldSnapshot.scaledValue {
            direction = .upward
        } else if newSnapshot.scaledValue < oldSnapshot.scaledValue {
            direction = .downward
        } else {
            direction = .stationary
        }

        let transitions = zip(oldSnapshot.digits, newSnapshot.digits)
            .enumerated()
            .map { index, pair in
                let (oldDigit, newDigit) = pair
                let steps: Int
                switch direction {
                case .upward:
                    steps = (newDigit.digit - oldDigit.digit + 10) % 10
                case .downward:
                    steps = (oldDigit.digit - newDigit.digit + 10) % 10
                case .stationary:
                    steps = 0
                }

                let visibilityChange: RollingDigitVisibilityChange
                switch (oldDigit.isVisible, newDigit.isVisible) {
                case (false, true): visibilityChange = .appears
                case (true, false): visibilityChange = .disappears
                default: visibilityChange = .unchanged
                }

                return RollingDigitTransition(
                    slotIndex: index,
                    fromDigit: oldDigit.digit,
                    toDigit: newDigit.digit,
                    direction: steps == 0 ? .stationary : direction,
                    rollSteps: steps,
                    visibilityChange: visibilityChange,
                    startsVisible: oldDigit.isVisible,
                    endsVisible: newDigit.isVisible
                )
            }

        return RollingNumberTransitionPlan(
            from: oldSnapshot,
            to: newSnapshot,
            direction: direction,
            slots: transitions
        )
    }

    private static func decimalDigitCount(_ value: UInt64) -> Int {
        if value == 0 { return 1 }
        var working = value
        var count = 0
        while working > 0 {
            count += 1
            working /= 10
        }
        return count
    }

    private static func powerOfTen(_ exponent: Int) throws -> UInt64 {
        guard exponent >= 0, exponent <= 15 else {
            throw RollingNumberError.invalidLayout
        }
        var value: UInt64 = 1
        for _ in 0..<exponent {
            let (next, overflow) = value.multipliedReportingOverflow(by: 10)
            guard !overflow else { throw RollingNumberError.invalidLayout }
            value = next
        }
        return value
    }
}