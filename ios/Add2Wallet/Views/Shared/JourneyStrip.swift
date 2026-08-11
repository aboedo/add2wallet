import SwiftUI

/// A leg, laid out the way a boarding pass lays one out: both ends, with the
/// journey drawn between them.
///
/// The itinerary row has to fit this into one line of a list, so it compresses
/// it to "08:15 → 11:40". Here there is a whole card and no reason to compress:
/// each end gets its place, its clock, its date and its timezone, and nothing
/// has to be inferred from the order of two numbers.
struct JourneyStrip: View {
    let segment: PassSegment
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeManager.Spacing.md) {
            if let service = segment.serviceLine {
                Text(service)
                    .font(ThemeManager.Typography.footnote)
                    .foregroundColor(ThemeManager.Colors.textSecondary)
            }

            HStack(alignment: .top, spacing: ThemeManager.Spacing.sm) {
                end(
                    place: segment.origin,
                    time: segment.departTime,
                    day: PassSegment.dayLabel(segment.departDate),
                    zone: segment.departZoneLabel,
                    alignment: .leading
                )

                VStack(spacing: ThemeManager.Spacing.hairline) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: ThemeManager.IconSize.inline, weight: .semibold))
                        .foregroundColor(accent)
                    // The only place the overnight marker can go without
                    // attaching itself to one of the two clocks and looking
                    // like part of the time.
                    if let overnight = segment.overnightSuffix {
                        Text(overnight)
                            .font(ThemeManager.Typography.caption)
                            .foregroundColor(ThemeManager.Colors.textTertiary)
                    }
                }
                .padding(.top, ThemeManager.Spacing.xs)

                end(
                    place: segment.destination,
                    time: segment.arriveTime,
                    day: PassSegment.dayLabel(segment.arriveDate),
                    zone: segment.arriveZoneLabel,
                    alignment: .trailing
                )
            }
        }
    }

    @ViewBuilder
    private func end(
        place: String?,
        time: String?,
        day: String?,
        zone: String?,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: ThemeManager.Spacing.hairline) {
            if let place {
                Text(place)
                    .font(ThemeManager.Typography.title2)
                    .foregroundColor(ThemeManager.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            if let time {
                HStack(spacing: ThemeManager.Spacing.xs) {
                    Text(time)
                        .font(ThemeManager.Typography.bodyMonospaced)
                        .foregroundColor(ThemeManager.Colors.textPrimary)
                    if let zone {
                        Text(zone)
                            .font(ThemeManager.Typography.caption)
                            .foregroundColor(ThemeManager.Colors.textTertiary)
                    }
                }
            }

            if let day {
                Text(day)
                    .font(ThemeManager.Typography.caption)
                    .foregroundColor(ThemeManager.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

#Preview {
    JourneyStrip(
        segment: PassSegment(
            page: nil,
            label: nil,
            origin: "GRU",
            destination: "MAD",
            departDate: "2026-10-10",
            departTime: "13:35",
            arriveDate: "2026-10-11",
            arriveTime: "05:50",
            departTimezone: "America/Sao_Paulo",
            arriveTimezone: "Europe/Madrid",
            carrier: "Iberia",
            vehicleInfo: "IB 6825",
            seatInfo: "22F",
            travelClass: "Economy",
            confirmationNumber: "QJ7T2M",
            traveler: nil,
            notes: nil
        ),
        accent: .blue
    )
    .padding()
}
