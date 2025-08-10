import SwiftUI
import SwiftData

struct SavedPassesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPass.createdAt, order: .reverse) private var savedPasses: [SavedPass]
    @State private var selectedPass: SavedPass?
    @State private var selectedTab = 0
    
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
            Group {
                if savedPasses.isEmpty {
                    emptyStateView
                } else {
                    passListView
                }
            }
            .navigationTitle("My Passes")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $selectedPass) { pass in
            SavedPassDetailView(savedPass: pass)
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
                    .foregroundColor(.secondary) +
                Text("generating your first Pass")
                    .foregroundColor(.blue)
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
                Section(header: Text(month)) {
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
        .background(Color(.systemGroupedBackground))
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
        HStack(spacing: 12) {
            // Pass type icon
            passIcon
            
            VStack(alignment: .leading, spacing: 4) {
                // Top row: Pass title
                Text(pass.displayTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Bottom row: Venue and ticket count on left (separate lines), Date on right
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Venue on its own line
                        if !pass.displayVenue.isEmpty {
                            Text(pass.displayVenue)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        // Ticket count on separate line
                        if pass.passCount > 1 {
                            Text("\(pass.passCount) tickets")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(passColor.opacity(0.15))
                                .foregroundColor(passColor)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Spacer()
                    
                    // Date on bottom right - use same format as SavedPassDetailView
                    VStack(alignment: .trailing) {
                        if let metadata = pass.metadata,
                           let dateTimeString = PassDateTimeFormatter.combineDateTime(date: metadata.date, time: metadata.time) {
                            Text(dateTimeString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if let eventDate = pass.eventDate, !eventDate.isEmpty {
                            Text(PassDateTimeFormatter.formatEventDate(eventDate))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(PassDateTimeFormatter.formatDateLocalized(pass.createdAt))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    
    @ViewBuilder
    private var passIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(passColor)
                .frame(width: 40, height: 40)
            
            Image(systemName: passIconName)
                .font(.system(size: 20, weight: .medium))
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