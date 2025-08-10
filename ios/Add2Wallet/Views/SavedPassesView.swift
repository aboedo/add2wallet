import SwiftUI
import SwiftData

struct SavedPassesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPass.createdAt, order: .reverse) private var savedPasses: [SavedPass]
    @State private var selectedPass: SavedPass?
    @State private var selectedTab = 0
    
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
            ForEach(savedPasses) { pass in
                PassRowView(pass: pass) {
                    selectedPass = pass
                }
            }
            .onDelete(perform: deletePasses)
        }
        .listStyle(InsetGroupedListStyle())
        .background(Color(.systemGroupedBackground))
    }
    
    private func deletePasses(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(savedPasses[index])
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
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Pass type icon
                passIcon
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(pass.displayTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if pass.passCount > 1 {
                            Text("\(pass.passCount) passes")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                    }
                    
                    if !pass.displaySubtitle.isEmpty {
                        Text(pass.displaySubtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Text("Created \(pass.formattedCreatedAt)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
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
        switch pass.passType.lowercased() {
        case let type where type.contains("event"):
            return .orange
        case let type where type.contains("concert"):
            return .purple
        case let type where type.contains("flight"):
            return .blue
        case let type where type.contains("movie"):
            return .red
        case let type where type.contains("sport"):
            return .green
        case let type where type.contains("transit"):
            return .cyan
        default:
            return .gray
        }
    }
    
    private var passIconName: String {
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