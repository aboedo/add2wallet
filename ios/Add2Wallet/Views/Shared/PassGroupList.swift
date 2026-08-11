import SwiftUI

/// Lists every pass in a saved group with its own detail.
///
/// A multi-leg booking used to render as a single opaque "Add 8 to Wallet"
/// button, so there was no way to tell which pass was which leg. Each row now
/// shows that pass's route, times, seat and reference, and can be added on its
/// own.
struct PassGroupList: View {
    let tickets: [PassTicketInfo]
    let groupName: String?
    var onAdd: ((PassTicketInfo) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeManager.Spacing.sm) {
            header

            ForEach(tickets) { ticket in
                PassGroupRow(ticket: ticket, onAdd: onAdd)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: ThemeManager.Spacing.xs) {
            Text(groupName ?? "Passes")
                .font(ThemeManager.Typography.title2)
                .foregroundColor(ThemeManager.Colors.textPrimary)
            Spacer()
            Text("\(tickets.count)")
                .font(ThemeManager.Typography.footnote)
                .foregroundColor(ThemeManager.Colors.textTertiary)
                .accessibilityLabel("\(tickets.count) passes")
        }
    }
}

private struct PassGroupRow: View {
    let ticket: PassTicketInfo
    var onAdd: ((PassTicketInfo) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeManager.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(ticket.route ?? ticket.title)
                    .font(ThemeManager.Typography.bodySemibold)
                    .foregroundColor(ThemeManager.Colors.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: ThemeManager.Spacing.xs)

                if let onAdd {
                    Button {
                        ThemeManager.Haptics.light()
                        onAdd(ticket)
                    } label: {
                        Image(systemName: "wallet.pass")
                            .font(ThemeManager.Typography.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(ThemeManager.Colors.interactive)
                    .accessibilityLabel("Add \(ticket.route ?? ticket.title) to Wallet")
                }
            }

            if ticket.route != nil, ticket.title != ticket.route {
                Text(ticket.title)
                    .font(ThemeManager.Typography.caption)
                    .foregroundColor(ThemeManager.Colors.textSecondary)
                    .lineLimit(1)
            }

            if !ticket.details.isEmpty {
                VStack(alignment: .leading, spacing: ThemeManager.Spacing.hairline) {
                    ForEach(ticket.details) { detail in
                        HStack(alignment: .firstTextBaseline, spacing: ThemeManager.Spacing.xs) {
                            Text(detail.label)
                                .font(ThemeManager.Typography.caption)
                                .foregroundColor(ThemeManager.Colors.textTertiary)
                                .frame(width: 74, alignment: .leading)
                            Text(detail.value)
                                .font(ThemeManager.Typography.caption)
                                .foregroundColor(ThemeManager.Colors.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.top, ThemeManager.Spacing.hairline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ThemeManager.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium, style: .continuous)
                .fill(ThemeManager.Colors.surfaceCard)
        )
    }
}
