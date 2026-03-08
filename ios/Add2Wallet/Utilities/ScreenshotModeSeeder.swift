import SwiftData
import Foundation

struct ScreenshotModeSeeder {
    static func isScreenshotMode() -> Bool {
        ProcessInfo.processInfo.arguments.contains("-SCREENSHOT_MODE")
    }

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        guard isScreenshotMode() else { return }

        // Skip onboarding
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")

        // Clear existing passes
        try? context.delete(model: SavedPass.self)

        let calendar = Calendar.current
        let now = Date()

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"

        let fakeData: [(title: String, venue: String, city: String, passType: String, daysFromNow: Int)] = [
            ("Coldplay World Tour", "Camp Nou", "Barcelona", "concert", 8),
            ("Real Madrid vs Barcelona", "Santiago Bernabéu", "Madrid", "sports", 15),
            ("Hamilton", "Victoria Palace Theatre", "London", "theatre", 22),
            ("Eiffel Tower", "Champ de Mars", "Paris", "attraction", 35),
            ("Musée d'Orsay", "Rue de la Légion d'Honneur", "Paris", "museum", 36),
            ("JFK → CDG", "John F. Kennedy Intl.", "New York", "flight", 50),
        ]

        for (index, data) in fakeData.enumerated() {
            let eventDate = calendar.date(byAdding: .day, value: data.daysFromNow, to: now)!
            let pass = SavedPass(
                id: "screenshot-\(index)",
                createdAt: calendar.date(byAdding: .day, value: -index, to: now)!,
                passType: data.passType,
                title: data.title,
                eventDate: formatter.string(from: eventDate),
                venue: data.venue,
                city: data.city
            )
            context.insert(pass)
        }

        try? context.save()
    }
}
