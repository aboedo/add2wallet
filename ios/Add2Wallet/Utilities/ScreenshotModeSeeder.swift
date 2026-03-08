import SwiftData
import Foundation

struct ScreenshotModeSeeder {
    static func isScreenshotMode() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard.string(forKey: "SCREENSHOT_MODE")
        // Maestro launchApp arguments can appear as:
        // - ProcessInfo.arguments: "SCREENSHOT_MODE", "-SCREENSHOT_MODE", "SCREENSHOT_MODE=1"
        // - ProcessInfo.environment: SCREENSHOT_MODE=1
        // - UserDefaults: SCREENSHOT_MODE = "1"
        return env["SCREENSHOT_MODE"] == "1"
            || defaults == "1"
            || args.contains("SCREENSHOT_MODE")
            || args.contains("-SCREENSHOT_MODE")
            || args.contains("SCREENSHOT_MODE=1")
    }

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        print("🖼️ ScreenshotMode check — args: \(args), env[SCREENSHOT_MODE]: \(env["SCREENSHOT_MODE"] ?? "nil")")
        guard isScreenshotMode() else {
            print("🖼️ Not in screenshot mode, skipping seed")
            return
        }
        print("🖼️ SCREENSHOT MODE ACTIVE — seeding fake passes")

        // Skip onboarding
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")

        // Clear existing passes (fetch explicitly to ensure deletion)
        let fetchDescriptor = FetchDescriptor<SavedPass>()
        if let existingPasses = try? context.fetch(fetchDescriptor) {
            for pass in existingPasses {
                context.delete(pass)
            }
        }
        try? context.save()

        let calendar = Calendar.current
        let now = Date()

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"

        struct FakePassData {
            let title: String
            let venue: String
            let city: String
            let passType: String
            let daysFromNow: Int
            let color: String  // rgb() string
        }

        let fakeData: [FakePassData] = [
            FakePassData(title: "Coldplay World Tour",       venue: "Camp Nou",                    city: "Barcelona", passType: "concert",    daysFromNow: 8,  color: "rgb(255,45,85)"),
            FakePassData(title: "Real Madrid vs Barcelona",  venue: "Santiago Bernabéu",           city: "Madrid",    passType: "sports",     daysFromNow: 15, color: "rgb(52,199,89)"),
            FakePassData(title: "Hamilton",                  venue: "Victoria Palace Theatre",     city: "London",    passType: "theatre",    daysFromNow: 22, color: "rgb(94,92,230)"),
            FakePassData(title: "Eiffel Tower",              venue: "Champ de Mars",               city: "Paris",     passType: "attraction", daysFromNow: 35, color: "rgb(255,196,0)"),
            FakePassData(title: "Musée d'Orsay",            venue: "Rue de la Légion d'Honneur",  city: "Paris",     passType: "museum",     daysFromNow: 36, color: "rgb(255,140,0)"),
            FakePassData(title: "JFK → CDG",                venue: "John F. Kennedy Intl.",       city: "New York",  passType: "flight",     daysFromNow: 50, color: "rgb(0,122,255)"),
        ]

        for (index, data) in fakeData.enumerated() {
            let eventDate = calendar.date(byAdding: .day, value: data.daysFromNow, to: now)!
            let metadata = EnhancedPassMetadata(
                eventType: data.passType,
                eventName: data.title,
                title: data.title,
                description: nil,
                date: formatter.string(from: eventDate),
                time: nil,
                duration: nil,
                venueName: data.venue,
                venueAddress: nil,
                city: data.city,
                stateCountry: nil,
                latitude: nil,
                longitude: nil,
                organizer: nil,
                performerArtist: nil,
                seatInfo: nil,
                barcodeData: nil,
                price: nil,
                confirmationNumber: nil,
                gateInfo: nil,
                eventDescription: nil,
                venueType: nil,
                capacity: nil,
                website: nil,
                phone: nil,
                nearbyLandmarks: nil,
                publicTransport: nil,
                parkingInfo: nil,
                ageRestriction: nil,
                dressCode: nil,
                weatherConsiderations: nil,
                amenities: nil,
                accessibility: nil,
                aiProcessed: nil,
                confidenceScore: nil,
                processingTimestamp: nil,
                modelUsed: nil,
                enrichmentCompleted: nil,
                backgroundColor: data.color,
                foregroundColor: "rgb(255,255,255)",
                labelColor: "rgb(255,255,255)",
                multipleEvents: nil,
                upcomingEvents: nil,
                venuePlaceId: nil,
                performerNames: nil,
                exhibitName: nil,
                hasAssignedSeating: nil,
                eventUrls: nil
            )
            let pass = SavedPass(
                id: "screenshot-\(index)",
                createdAt: calendar.date(byAdding: .day, value: -index, to: now)!,
                passType: data.passType,
                title: data.title,
                eventDate: formatter.string(from: eventDate),
                venue: data.venue,
                city: data.city,
                metadata: metadata
            )
            context.insert(pass)
        }

        try? context.save()
    }
}
