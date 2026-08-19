import NembraCore
import SwiftUI

private enum MileageActivityMode: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case cumulative

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Durable accepted-day mileage, never the scooter power-session trip counter.
struct DailyMileageActivityView: View {
    @Environment(DailyRidePresentationStore.self) private var daily
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var mode: MileageActivityMode = .daily
    @State private var selectedDay: RideLocalDay?

    private let onViewRides: (RideLocalDay) -> Void

    init(onViewRides: @escaping (RideLocalDay) -> Void = { _ in }) {
        self.onViewRides = onViewRides
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NembraMetrics.section) {
            summaryStrip
            activityHero
        }
        .padding(.vertical, 8)
        .task(id: daily.recentDays.count) {
            chooseInitialDayIfNeeded()
        }
    }

    // MARK: - Archive summary

    private var summaryStrip: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    ForEach(Array(summaryMetrics.enumerated()), id: \.element.id) { index, metric in
                        summaryMetric(metric, horizontalAlignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)

                        if index < summaryMetrics.count - 1 {
                            Divider().overlay(NembraColor.quietLine)
                        }
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(summaryMetrics.enumerated()), id: \.element.id) { index, metric in
                        summaryMetric(metric, horizontalAlignment: .center)
                            .frame(maxWidth: .infinity)

                        if index < summaryMetrics.count - 1 {
                            Rectangle()
                                .fill(NembraColor.quietLine)
                                .frame(width: 1, height: 44)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 4 : 16)
        .background(
            NembraColor.quietSurface,
            in: RoundedRectangle(cornerRadius: NembraMetrics.controlRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: NembraMetrics.controlRadius, style: .continuous)
                .strokeBorder(NembraColor.quietLine)
        }
    }

    private func summaryMetric(
        _ metric: ArchiveSummaryMetric,
        horizontalAlignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: horizontalAlignment, spacing: 4) {
            Text(metric.value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(NembraColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(metric.title)
                .font(.caption)
                .foregroundStyle(NembraColor.secondaryText)
                .multilineTextAlignment(horizontalAlignment == .center ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(metric.accessibilityValue)
    }

    private var summaryMetrics: [ArchiveSummaryMetric] {
        let recent = aggregate(daily.recentDays)
        let best = daily.recentDays
            .compactMap { summary -> (day: RideLocalDay, meters: Double, availability: DailyRideMetricAvailability)? in
                guard let value = summary.distanceMeters.value else { return nil }
                return (summary.localDay, value, summary.distanceMeters.availability)
            }
            .max { $0.meters < $1.meters }
        let activeDays = daily.recentDays.filter { $0.rideCount > 0 }.count
        let streak = currentStreak

        return [
            ArchiveSummaryMetric(
                id: "recent-distance",
                value: distanceText(meters: recent.value),
                title: recent.isPartial ? "Known distance" : "Recent distance",
                accessibilityValue: metricAccessibilityValue(
                    distanceText(meters: recent.value),
                    availability: recent.availability
                )
            ),
            ArchiveSummaryMetric(
                id: "best-day",
                value: best.map { VehicleDisplayFormatting.distance(kilometers: $0.meters / 1_000) } ?? "—",
                title: best?.availability == .partial ? "Known best" : "Best day",
                accessibilityValue: best.map {
                    let qualifier = $0.availability == .partial ? "partial accepted evidence, " : ""
                    return "\(qualifier)\(VehicleDisplayFormatting.distance(kilometers: $0.meters / 1_000)) on \(formattedDay($0.day))"
                } ?? "No accepted distance evidence"
            ),
            ArchiveSummaryMetric(
                id: "current-streak",
                value: "\(streak)",
                title: "Day streak",
                accessibilityValue: streak == 1 ? "1 day" : "\(streak) consecutive days"
            ),
            ArchiveSummaryMetric(
                id: "active-days",
                value: "\(activeDays)",
                title: "Active days",
                accessibilityValue: activeDays == 1 ? "1 active day" : "\(activeDays) active days"
            )
        ]
    }

    // MARK: - Mileage activity hero

    private var activityHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            activityHeader

            switch daily.status {
            case .idle, .loading:
                loadingState
            case .unavailable, .failed:
                unavailableState
            case .ready:
                activityField
                selectedDayDetail
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(NembraColor.warmGraphite)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(NembraColor.gold.opacity(0.14))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NembraColor.gold.opacity(0.14))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    private var activityHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    activityTitle
                    modeTabs
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    activityTitle
                    Spacer(minLength: 8)
                    modeTabs
                }
            }
        }
    }

    private var activityTitle: some View {
        Text("Mileage activity")
            .font(.title2.weight(.bold))
            .foregroundStyle(NembraColor.primaryText)
            // Keep the tab-destination marker on one concrete accessibility
            // element. Applying it to the enclosing VStack makes SwiftUI
            // inherit the same identifier into unrelated chart and summary
            // descendants, masking their own identifiers in UI automation.
            .accessibilityIdentifier("rides.mileage-activity")
    }

    private var modeTabs: some View {
        HStack(spacing: 6) {
            ForEach(MileageActivityMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(option == mode ? .semibold : .regular))
                        .foregroundStyle(option == mode ? NembraColor.primaryText : NembraColor.secondaryText)
                        .padding(.horizontal, 7)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == mode ? .isSelected : [])
                .accessibilityIdentifier("rides.activity.mode.\(option.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mileage activity view")
    }

    @ViewBuilder
    private var activityField: some View {
        switch mode {
        case .daily:
            dailyActivityField
        case .weekly:
            periodActivityField(values: weeklyActivityValues, title: "Accepted miles by week")
        case .cumulative:
            periodActivityField(values: cumulativeActivityValues, title: "Cumulative accepted miles")
        }
    }

    private var dailyActivityField: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                weekdayLabels

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 7) {
                        ForEach(activityWeeks) { week in
                            activityWeekColumn(week)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.trailing)
            }

            intensityLegend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily accepted mileage chart")
        .accessibilityValue(selectedChartAccessibilityValue)
        .accessibilityHint("Swipe up or down with one finger to move the selected day.")
        .accessibilityAdjustableAction { direction in
            moveSelection(direction)
        }
        .accessibilityIdentifier("rides.activity.daily-chart")
    }

    private var weekdayLabels: some View {
        VStack(spacing: 7) {
            ForEach(Array(["M", "", "W", "", "F", "", "S"].enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(NembraColor.secondaryText)
                    .frame(width: 15, height: 18)
            }
        }
        .padding(.top, 21)
        .accessibilityHidden(true)
    }

    private func activityWeekColumn(_ week: ActivityWeek) -> some View {
        VStack(spacing: 7) {
            Text(week.monthLabel)
                .font(.caption2)
                .foregroundStyle(NembraColor.secondaryText)
                .frame(height: 14)
                .fixedSize()

            ForEach(week.days, id: \.day) { item in
                daySquare(item)
            }
        }
    }

    private func daySquare(_ item: ActivityDay) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fillColor(for: item.summary))
            .frame(width: 18, height: 18)
            .overlay {
                if selectedDay == item.day {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(NembraColor.primaryText, lineWidth: 2)
                        .padding(-2)
                } else if item.summary?.distanceMeters.availability == .partial {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(
                            NembraColor.gold,
                            style: StrokeStyle(lineWidth: 1.25, dash: [2, 2])
                        )
                } else if differentiateWithoutColor,
                          item.summary?.distanceMeters.value != nil {
                    Circle()
                        .fill(NembraColor.primaryText)
                        .frame(width: 4, height: 4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedDay = item.day
            }
            .accessibilityHidden(true)
    }

    private var intensityLegend: some View {
        HStack(spacing: 7) {
            Text("Less")
            ForEach(0..<4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(legendColor(level))
                    .frame(width: 14, height: 14)
            }
            Text("More")
        }
        .font(.caption2)
        .foregroundStyle(NembraColor.secondaryText)
        .accessibilityHidden(true)
    }

    private func periodActivityField(
        values: [PeriodActivityValue],
        title: String
    ) -> some View {
        let maximum = max(values.compactMap(\.meters).max() ?? 0, 1)

        return ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(values) { value in
                    Button {
                        if let day = value.selectionDay {
                            selectedDay = day
                        }
                    } label: {
                        VStack(spacing: 7) {
                            Spacer(minLength: 0)

                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(periodFillColor(value))
                                .frame(
                                    width: 30,
                                    height: periodHeight(value.meters, maximum: maximum)
                                )
                                .overlay {
                                    if value.isPartial {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(
                                                NembraColor.gold,
                                                style: StrokeStyle(lineWidth: 1.25, dash: [3, 2])
                                            )
                                    }
                                }

                            Text(value.shortLabel)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(NembraColor.secondaryText)
                        }
                        .frame(width: 46, height: 142)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(value.selectionDay == nil)
                    .accessibilityLabel(value.accessibilityLabel)
                    .accessibilityValue(value.accessibilityValue)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.trailing)
        .accessibilityLabel(title)
        .accessibilityIdentifier("rides.activity.\(mode.rawValue)-chart")
    }

    // MARK: - Selected day

    @ViewBuilder
    private var selectedDayDetail: some View {
        if let selectedDay,
           let item = activityDays.first(where: { $0.day == selectedDay }) {
            VStack(alignment: .leading, spacing: 16) {
                Divider().overlay(NembraColor.quietLine)

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 16) {
                        selectedDayIdentity(item)
                        selectedMetrics(item)
                    }
                } else {
                    HStack(alignment: .center, spacing: 14) {
                        selectedDayIdentity(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        selectedMetrics(item)
                    }
                }

                selectedDayAction(item)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func selectedDayIdentity(_ item: ActivityDay) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.day == currentDay ? "Today" : shortSelectedDay(item.day))
                .font(.headline.weight(.bold))
                .foregroundStyle(NembraColor.gold)
            Text(item.day == currentDay ? shortSelectedDay(item.day) : formattedDay(item.day))
                .font(.caption)
                .foregroundStyle(NembraColor.secondaryText)
        }
    }

    private func selectedMetrics(_ item: ActivityDay) -> some View {
        HStack(alignment: .center, spacing: 12) {
            selectedMetric(
                title: "Distance",
                value: distanceText(item.summary?.distanceMeters),
                availability: item.summary?.distanceMeters.availability
            )
            metricDivider
            selectedMetric(
                title: "Duration",
                value: durationText(item.summary?.durationSeconds),
                availability: item.summary?.durationSeconds.availability
            )
            metricDivider
            selectedMetric(
                title: "Rides",
                value: item.summary.map { "\($0.rideCount)" } ?? "—",
                availability: item.summary == nil ? .noEvidence : .complete
            )
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(NembraColor.quietLine)
            .frame(width: 1, height: 44)
            .accessibilityHidden(true)
    }

    private func selectedMetric(
        title: String,
        value: String,
        availability: DailyRideMetricAvailability?
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(NembraColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption)
                .foregroundStyle(NembraColor.secondaryText)
            if availability == .partial {
                Text("Partial")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(NembraColor.gold)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(metricAccessibilityValue(value, availability: availability))
    }

    @ViewBuilder
    private func selectedDayAction(_ item: ActivityDay) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                evidenceNote(item.summary)
                viewRidesButton(item)
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                evidenceNote(item.summary)
                Spacer(minLength: 8)
                viewRidesButton(item)
            }
        }
    }

    @ViewBuilder
    private func viewRidesButton(_ item: ActivityDay) -> some View {
        if let summary = item.summary, summary.rideCount > 0 {
            Button {
                onViewRides(item.day)
            } label: {
                HStack(spacing: 4) {
                    Text(summary.rideCount == 1 ? "View 1 ride" : "View \(summary.rideCount) rides")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NembraColor.gold)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows completed ride records that overlap this accepted local day.")
            .accessibilityIdentifier("rides.activity.view-rides")
        }
    }

    @ViewBuilder
    private func evidenceNote(_ summary: DailyRideSummary?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(summary == nil ? NembraColor.secondaryText : NembraColor.gold)
                .frame(width: 7, height: 7)
                .shadow(color: summary == nil ? .clear : NembraColor.gold.opacity(0.45), radius: 5)
                .accessibilityHidden(true)
            Text(evidenceNoteText(summary))
                .font(.caption)
                .foregroundStyle(NembraColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(NembraColor.gold)
            Text("Loading accepted mileage…")
                .font(.subheadline)
                .foregroundStyle(NembraColor.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
        .accessibilityIdentifier("rides.activity.loading")
    }

    private var unavailableState: some View {
        Label(
            daily.lastErrorMessage ?? "Accepted mileage is unavailable.",
            systemImage: "exclamationmark.triangle"
        )
        .font(.subheadline)
        .foregroundStyle(NembraColor.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .accessibilityIdentifier("rides.activity.unavailable")
    }

    // MARK: - Calendar projections

    private var activityDays: [ActivityDay] {
        var calendar = Calendar.current
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4

        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: .now),
              let firstWeekStart = calendar.date(
                  byAdding: .weekOfYear,
                  value: -12,
                  to: currentWeek.start
              ) else {
            return daily.recentDays
                .sorted { $0.localDay.startDate < $1.localDay.startDate }
                .suffix(91)
                .map { ActivityDay(day: $0.localDay, summary: $0) }
        }

        let acceptedByComponents = Dictionary(grouping: daily.recentDays) { summary in
            DayComponents(day: summary.localDay)
        }

        return (0..<91).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstWeekStart),
                  let generated = try? RideLocalDay(containing: date, calendar: calendar) else {
                return nil
            }
            let matches = acceptedByComponents[DayComponents(day: generated)] ?? []
            if matches.count == 1, let accepted = matches.first {
                return ActivityDay(day: accepted.localDay, summary: accepted)
            }
            if let exact = matches.first(where: { $0.localDay == generated }) {
                return ActivityDay(day: exact.localDay, summary: exact)
            }
            // More than one frozen day identity must never be silently combined.
            return ActivityDay(day: generated, summary: nil)
        }
    }

    private var activityWeeks: [ActivityWeek] {
        let days = activityDays
        var result: [ActivityWeek] = []
        var index = 0
        while index < days.count {
            let end = min(index + 7, days.count)
            let weekDays = Array(days[index..<end])
            let previousLast = result.last?.days.last?.day
            let currentLast = weekDays.last?.day
            let monthChanged = previousLast.map {
                $0.month != currentLast?.month || $0.year != currentLast?.year
            } ?? true
            result.append(
                ActivityWeek(
                    days: weekDays,
                    monthLabel: monthChanged ? currentLast.map(shortMonth) ?? "" : ""
                )
            )
            index = end
        }
        return result
    }

    private var weeklyActivityValues: [PeriodActivityValue] {
        activityWeeks.map { week in
            let summaries = week.days.compactMap(\.summary)
            let aggregated = aggregate(summaries)
            return PeriodActivityValue(
                id: week.id,
                meters: aggregated.value,
                isPartial: aggregated.isPartial,
                shortLabel: week.days.last.map { shortMonthDay($0.day) } ?? "—",
                selectionDay: week.days.last(where: { $0.summary != nil })?.day ?? week.days.last?.day,
                accessibilityLabel: week.days.first.map {
                    "Week of \(formattedDay($0.day))"
                } ?? "Week",
                accessibilityValue: metricAccessibilityValue(
                    distanceText(meters: aggregated.value),
                    availability: aggregated.availability
                )
            )
        }
    }

    private var cumulativeActivityValues: [PeriodActivityValue] {
        var knownMeters: Double = 0
        var hasEvidence = false
        var isPartial = false

        return activityWeeks.map { week in
            let aggregated = aggregate(week.days.compactMap(\.summary))
            if let value = aggregated.value {
                knownMeters += value
                hasEvidence = true
            }
            isPartial = isPartial || aggregated.isPartial
            let value = hasEvidence ? knownMeters : nil
            let availability: DailyRideMetricAvailability = hasEvidence
                ? (isPartial ? .partial : .complete)
                : .noEvidence
            return PeriodActivityValue(
                id: week.id,
                meters: value,
                isPartial: isPartial,
                shortLabel: week.days.last.map { shortMonthDay($0.day) } ?? "—",
                selectionDay: week.days.last(where: { $0.summary != nil })?.day ?? week.days.last?.day,
                accessibilityLabel: week.days.last.map {
                    "Through \(formattedDay($0.day))"
                } ?? "Cumulative mileage",
                accessibilityValue: metricAccessibilityValue(
                    distanceText(meters: value),
                    availability: availability
                )
            )
        }
    }

    private var currentDay: RideLocalDay? {
        try? RideLocalDay(containing: .now, calendar: .current)
    }

    private var currentStreak: Int {
        let activeDays = daily.recentDays
            .filter { $0.rideCount > 0 }
            .map(\.localDay)
            .sorted { $0.startDate > $1.startDate }
        guard let today = currentDay else { return 0 }

        let first: RideLocalDay?
        if let activeToday = activeDays.first(where: { $0 == today }) {
            first = activeToday
        } else {
            first = activeDays.first(where: {
                abs($0.endDate.timeIntervalSince(today.startDate)) < 1
            })
        }
        guard var cursor = first else { return 0 }

        var count = 1
        for candidate in activeDays where candidate != cursor {
            guard abs(candidate.endDate.timeIntervalSince(cursor.startDate)) < 1 else { continue }
            count += 1
            cursor = candidate
        }
        return count
    }

    private var maximumDailyDistance: Double {
        activityDays.compactMap { $0.summary?.distanceMeters.value }.max() ?? 0
    }

    private func chooseInitialDayIfNeeded() {
        let days = activityDays
        if let selectedDay, days.contains(where: { $0.day == selectedDay }) { return }
        selectedDay = currentDay.flatMap { current in
            days.first(where: { DayComponents(day: $0.day) == DayComponents(day: current) })?.day
        } ?? days.last?.day
    }

    private func moveSelection(_ direction: AccessibilityAdjustmentDirection) {
        let days = activityDays
        guard !days.isEmpty else { return }
        let currentIndex = selectedDay.flatMap { day in
            days.firstIndex(where: { $0.day == day })
        } ?? (days.count - 1)

        let nextIndex: Int
        switch direction {
        case .increment:
            nextIndex = min(currentIndex + 1, days.count - 1)
        case .decrement:
            nextIndex = max(currentIndex - 1, 0)
        @unknown default:
            nextIndex = currentIndex
        }
        selectedDay = days[nextIndex].day
    }

    // MARK: - Evidence formatting

    private func aggregate(_ summaries: [DailyRideSummary]) -> AggregateMetric {
        let values = summaries.compactMap { $0.distanceMeters.value }
        let includedSegments = summaries.reduce(0) { $0 + $1.distanceMeters.includedSegmentCount }
        let excludedSegments = summaries.reduce(0) { $0 + $1.distanceMeters.excludedSegmentCount }
        let hasIncompleteRideEvidence = summaries.contains {
            $0.rideCount > 0 && $0.distanceMeters.availability != .complete
        }

        let availability: DailyRideMetricAvailability
        if summaries.isEmpty {
            availability = .noEvidence
        } else if values.isEmpty {
            availability = .unavailable
        } else if hasIncompleteRideEvidence {
            availability = .partial
        } else {
            availability = .complete
        }

        return AggregateMetric(
            value: values.isEmpty ? nil : values.reduce(0, +),
            availability: availability,
            includedSegmentCount: includedSegments,
            excludedSegmentCount: excludedSegments
        )
    }

    private func fillColor(for summary: DailyRideSummary?) -> Color {
        guard let distance = summary?.distanceMeters.value, distance > 0 else {
            return NembraColor.quietSurface
        }
        let normalized = min(max(distance / max(maximumDailyDistance, 1), 0), 1)
        return NembraColor.gold.opacity(0.28 + (0.72 * normalized))
    }

    private func legendColor(_ level: Int) -> Color {
        level == 0
            ? NembraColor.quietSurface
            : NembraColor.gold.opacity(0.18 + (Double(level) * 0.22))
    }

    private func periodFillColor(_ value: PeriodActivityValue) -> Color {
        guard let meters = value.meters, meters > 0 else { return NembraColor.quietSurface }
        return value.isPartial ? NembraColor.deepGold.opacity(0.72) : NembraColor.gold.opacity(0.88)
    }

    private func periodHeight(_ meters: Double?, maximum: Double) -> CGFloat {
        guard let meters, meters > 0 else { return 12 }
        let normalized = min(max(meters / maximum, 0), 1)
        return 18 + (74 * normalized)
    }

    private func distanceText(_ metric: DailyRideMetricSummary?) -> String {
        guard let meters = metric?.value else { return "—" }
        return VehicleDisplayFormatting.distance(kilometers: meters / 1_000)
    }

    private func distanceText(meters: Double?) -> String {
        guard let meters else { return "—" }
        return VehicleDisplayFormatting.distance(kilometers: meters / 1_000)
    }

    private func durationText(_ metric: DailyRideMetricSummary?) -> String {
        guard let seconds = metric?.value else { return "—" }
        let minutes = Int(max(seconds, 0) / 60)
        if seconds > 0, minutes == 0 { return "<1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func evidenceNoteText(_ summary: DailyRideSummary?) -> String {
        guard let summary else { return "No accepted ride evidence for this day." }
        if summary.distanceMeters.availability == .partial
            || summary.durationSeconds.availability == .partial {
            return "Known totals are partial; gaps were not invented."
        }
        if summary.containsRecoveredRide {
            return "Includes a ride recovered from a durable checkpoint."
        }
        return summary.rideCount == 1
            ? "1 legitimate ride contributes to this day."
            : "\(summary.rideCount) legitimate rides contribute to this day."
    }

    private var selectedChartAccessibilityValue: String {
        guard let selectedDay,
              let item = activityDays.first(where: { $0.day == selectedDay }) else {
            return "No day selected"
        }
        return dayAccessibilityLabel(item)
    }

    private func dayAccessibilityLabel(_ item: ActivityDay) -> String {
        guard let summary = item.summary else {
            return "\(formattedDay(item.day)), no accepted ride evidence"
        }
        let recovery = summary.containsRecoveredRide ? ", includes recovered ride" : ""
        return "\(formattedDay(item.day)), \(distanceText(summary.distanceMeters)), \(durationText(summary.durationSeconds)), \(summary.rideCount) rides, \(availabilityLabel(summary.distanceMeters.availability)) distance evidence\(recovery)"
    }

    private func metricAccessibilityValue(
        _ value: String,
        availability: DailyRideMetricAvailability?
    ) -> String {
        guard let availability else { return value }
        return "\(value), \(availabilityLabel(availability)) evidence"
    }

    private func availabilityLabel(_ availability: DailyRideMetricAvailability) -> String {
        switch availability {
        case .noEvidence: "no accepted"
        case .unavailable: "unavailable"
        case .partial: "partial"
        case .complete: "complete"
        }
    }

    private func formattedDay(_ day: RideLocalDay) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: day.timeZoneIdentifier)
        formatter.dateStyle = .medium
        return formatter.string(from: day.startDate)
    }

    private func shortSelectedDay(_ day: RideLocalDay) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: day.timeZoneIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: day.startDate)
    }

    private func shortMonth(_ day: RideLocalDay) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: day.timeZoneIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: day.startDate)
    }

    private func shortMonthDay(_ day: RideLocalDay) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: day.timeZoneIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: day.startDate)
    }
}

private struct ActivityDay {
    let day: RideLocalDay
    let summary: DailyRideSummary?
}

private struct ActivityWeek: Identifiable {
    let days: [ActivityDay]
    let monthLabel: String

    var id: RideLocalDay { days[0].day }
}

private struct DayComponents: Hashable {
    let calendarIdentifier: String
    let era: Int
    let year: Int
    let month: Int
    let day: Int

    init(day: RideLocalDay) {
        calendarIdentifier = day.calendarIdentifier
        era = day.era
        year = day.year
        month = day.month
        self.day = day.day
    }
}

private struct AggregateMetric {
    let value: Double?
    let availability: DailyRideMetricAvailability
    let includedSegmentCount: Int
    let excludedSegmentCount: Int

    var isPartial: Bool { availability == .partial }
}

private struct ArchiveSummaryMetric: Identifiable {
    let id: String
    let value: String
    let title: String
    let accessibilityValue: String
}

private struct PeriodActivityValue: Identifiable {
    let id: RideLocalDay
    let meters: Double?
    let isPartial: Bool
    let shortLabel: String
    let selectionDay: RideLocalDay?
    let accessibilityLabel: String
    let accessibilityValue: String
}
