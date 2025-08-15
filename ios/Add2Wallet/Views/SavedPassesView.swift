import SwiftUI
import SwiftData
import RevenueCatUI
import StoreKit
import CloudKit

struct SavedPassesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPass.createdAt, order: .reverse) private var savedPasses: [SavedPass]
    @State private var selectedPass: SavedPass?
    @State private var selectedTab = 0
    @State private var showingCustomerCenter = false
    
    // Group passes by month based on event date (fallback to creation date)
    private var groupedPasses: [(String, [SavedPass])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        
        let grouped = Dictionary(grouping: savedPasses) { pass in
            let dateToUse = eventDateOrFallback(for: pass)
            return formatter.string(from: dateToUse)
        }
        
        return grouped.sorted { $0.value.first!.eventDateOrFallback > $1.value.first!.eventDateOrFallback }
            .map { ($0.key, $0.value.sorted { $0.eventDateOrFallback > $1.eventDateOrFallback }) }
    }
    
    // Helper to get event date or fallback to creation date
    private func eventDateOrFallback(for pass: SavedPass) -> Date {
        return pass.eventDateOrFallback
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if savedPasses.isEmpty {
                    emptyStateView
                } else {
                    passListView
                }
            }
            .navigationTitle("My Passes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingCustomerCenter = true
                    }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(item: $selectedPass) { pass in
            SavedPassDetailView(savedPass: pass)
        }
        .sheet(isPresented: $showingCustomerCenter) {
            CustomerCenterView()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Passes Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Group {
                Text("Start by ")
                    .foregroundColor(ThemeManager.Colors.textSecondary) +
                Text("generating your first Pass")
                    .foregroundColor(ThemeManager.Colors.brandPrimary)
                    .underline()
            }
            .font(.body)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            .onTapGesture {
                // Switch to Generate Pass tab
                NotificationCenter.default.post(
                    name: NSNotification.Name("SwitchToGeneratePassTab"),
                    object: nil
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    private var passListView: some View {
        List {
            ForEach(groupedPasses, id: \.0) { month, passes in
                Section(header: 
                    Text(month.uppercased())
                        .font(ThemeManager.Typography.sectionHeader)
                        .foregroundColor(ThemeManager.Colors.textSecondary)
                        .padding(.top, ThemeManager.Spacing.sm)
                ) {
                    ForEach(passes) { pass in
                        PassRowView(pass: pass) {
                            selectedPass = pass
                        }
                    }
                    .onDelete { offsets in
                        deletePassesInSection(passes: passes, offsets: offsets)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .background(ThemeManager.Colors.surfaceDefault)
    }
    
    private func deletePassesInSection(passes: [SavedPass], offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(passes[index])
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Error deleting passes: \(error)")
        }
    }
}

struct PassRowView: View {
    let pass: SavedPass
    let onTap: () -> Void
    
    var body: some View {
        ThemeManager.ComponentStyle.listRowWithStripe(accentColor: passColor) {
            HStack(spacing: ThemeManager.Spacing.md) {
                // Pass type icon
                passIcon
                
                VStack(alignment: .leading, spacing: ThemeManager.Spacing.xs) {
                    // Title row
                    Text(pass.displayTitle)
                        .font(ThemeManager.Typography.bodySemibold)
                        .foregroundColor(ThemeManager.Colors.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Venue row (full width)
                    if !pass.displayVenue.isEmpty {
                        Text(pass.displayVenue)
                            .font(ThemeManager.Typography.footnote)
                            .foregroundColor(ThemeManager.Colors.textSecondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Bottom row: Ticket count (left) + Date (right)
                    HStack(alignment: .bottom) {
                        // Ticket count badge on bottom left
                        if pass.passCount > 1 {
                            Text("\(pass.passCount) tickets")
                                .font(ThemeManager.Typography.caption)
                                .padding(.horizontal, ThemeManager.Spacing.xs)
                                .padding(.vertical, ThemeManager.Spacing.xs / 2)
                                .background(passColor.opacity(0.15))
                                .foregroundColor(passColor)
                                .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        // Date on bottom right - monospaced
                        if let metadata = pass.metadata,
                           let dateTimeString = PassDateTimeFormatter.combineDateTime(date: metadata.date, time: metadata.time) {
                            Text(dateTimeString)
                                .font(ThemeManager.Typography.captionMonospaced)
                                .foregroundColor(ThemeManager.Colors.textSecondary)
                        } else if let eventDate = pass.eventDate, !eventDate.isEmpty {
                            Text(PassDateTimeFormatter.formatEventDate(eventDate))
                                .font(ThemeManager.Typography.captionMonospaced)
                                .foregroundColor(ThemeManager.Colors.textSecondary)
                        } else {
                            Text(PassDateTimeFormatter.formatDateLocalized(pass.createdAt))
                                .font(ThemeManager.Typography.captionMonospaced)
                                .foregroundColor(ThemeManager.Colors.textSecondary)
                        }
                    }
                }
                
                // Chevron indicator
                Image(systemName: "chevron.right")
                    .font(ThemeManager.Typography.caption)
                    .foregroundColor(ThemeManager.Colors.textTertiary)
            }
            .padding(.vertical, ThemeManager.Spacing.sm)
            .padding(.trailing, ThemeManager.Spacing.sm)
            .contentShape(Rectangle())
            .onTapGesture {
                ThemeManager.Haptics.selection()
                onTap()
            }
        }
    }
    
    
    @ViewBuilder
    private var passIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.small)
                .fill(passColor)
                .frame(width: 28, height: 28) // Consistent icon size as specified
            
            Image(systemName: passIconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
        }
    }
    
    private var passColor: Color {
        return PassColorUtils.getPassColor(metadata: pass.metadata, passType: pass.passType)
    }
    
    
    private var passIconName: String {
        // Try to use metadata for better icon matching
        if let metadata = pass.metadata {
            let eventType = (metadata.eventType ?? pass.passType).lowercased()
            
            switch eventType {
            case let type where type.contains("museum") || type.contains("gallery") || type.contains("exhibition"):
                return "building.columns"
            case let type where type.contains("concert") || type.contains("music") || type.contains("band"):
                return "music.note"
            case let type where type.contains("festival"):
                return "star.circle"
            case let type where type.contains("event") || type.contains("conference"):
                return "calendar"
            case let type where type.contains("flight") || type.contains("airline") || type.contains("boarding"):
                return "airplane"
            case let type where type.contains("movie") || type.contains("cinema") || type.contains("film"):
                return "tv"
            case let type where type.contains("sport") || type.contains("game") || type.contains("match") || type.contains("stadium"):
                return "sportscourt"
            case let type where type.contains("basketball"):
                return "basketball"
            case let type where type.contains("football") || type.contains("soccer"):
                return "soccerball"
            case let type where type.contains("baseball"):
                return "baseball"
            case let type where type.contains("transit") || type.contains("train") || type.contains("railway"):
                return "train.side.front.car"
            case let type where type.contains("bus"):
                return "bus"
            case let type where type.contains("ferry") || type.contains("boat"):
                return "ferry"
            case let type where type.contains("theatre") || type.contains("theater") || type.contains("play") || type.contains("broadway"):
                return "theatermasks"
            case let type where type.contains("parking"):
                return "parkingsign"
            case let type where type.contains("hotel") || type.contains("accommodation"):
                return "bed.double"
            case let type where type.contains("restaurant") || type.contains("dining"):
                return "fork.knife"
            case let type where type.contains("ticket"):
                return "ticket"
            default:
                return "wallet.pass"
            }
        }
        
        // Fallback to basic pass type
        switch pass.passType.lowercased() {
        case let type where type.contains("event"):
            return "calendar"
        case let type where type.contains("concert"):
            return "music.note"
        case let type where type.contains("flight"):
            return "airplane"
        case let type where type.contains("movie"):
            return "tv"
        case let type where type.contains("sport"):
            return "sportscourt"
        case let type where type.contains("transit"):
            return "train.side.front.car"
        default:
            return "wallet.pass"
        }
    }
    
    private func requestAppRating() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            if #available(iOS 14.0, *) {
                SKStoreReviewController.requestReview(in: scene)
            } else {
                SKStoreReviewController.requestReview()
            }
        }
    }
    
    private func sendFeedbackEmail(appUserID: String) {
        let email = "support@add2wallet.app"
        let subject = "Add2Wallet Feedback"
        let body = """
        
        
        ---
        App User ID: \(appUserID)
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
        iOS Version: \(UIDevice.current.systemVersion)
        """
        
        let emailURL = "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: emailURL) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: SavedPass.self, configurations: config)
    
    // Add sample data
    let samplePass = SavedPass(
        passType: "Concert",
        title: "Taylor Swift Concert",
        eventDate: "Dec 15, 2024",
        venue: "Madison Square Garden",
        city: "New York, NY"
    )
    container.mainContext.insert(samplePass)
    
    return SavedPassesView()
        .modelContainer(container)
}