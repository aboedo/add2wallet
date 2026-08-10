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
        // The backend sends ISO dates and `PassDateTimeFormatter` only parses
        // those. Seeding "Aug 25, 2026" made every seeded pass silently lose
        // its date, so the screenshots lied about what the app renders.
        formatter.dateFormat = "yyyy-MM-dd"

        struct FakePassData {
            let title: String
            let venue: String
            let city: String
            let passType: String
            let daysFromNow: Int
            let color: String  // rgb() string
            // A journey's legs. Without these the seeded library has no travel
            // in it, so grouping never fires and the trip screens cannot be
            // seen at all — which is how they went unverified.
            var origin: String? = nil
            var destination: String? = nil
            var departTime: String? = nil
            var seat: String? = nil
            var latitude: Double? = nil
            var longitude: Double? = nil
        }

        let fakeData: [FakePassData] = [
            FakePassData(title: "Coldplay World Tour",       venue: "Camp Nou",                    city: "Barcelona", passType: "concert",    daysFromNow: 8,  color: "rgb(255,45,85)"),
            FakePassData(title: "Real Madrid vs Barcelona",  venue: "Santiago Bernabéu",           city: "Madrid",    passType: "sports",     daysFromNow: 15, color: "rgb(52,199,89)"),
            FakePassData(title: "Hamilton",                  venue: "Victoria Palace Theatre",     city: "London",    passType: "theatre",    daysFromNow: 22, color: "rgb(94,92,230)"),
            FakePassData(title: "Eiffel Tower",              venue: "Champ de Mars",               city: "Paris",     passType: "attraction", daysFromNow: 35, color: "rgb(255,196,0)"),
            FakePassData(title: "Musée d'Orsay",            venue: "Rue de la Légion d'Honneur",  city: "Paris",     passType: "museum",     daysFromNow: 36, color: "rgb(255,140,0)"),
            FakePassData(title: "JFK → CDG",                venue: "John F. Kennedy Intl.",       city: "New York",  passType: "flight",     daysFromNow: 50, color: "rgb(0,122,255)"),

            // One real journey: out of Montevideo, three days in Madrid, home
            // again. The return is what closes the trip.
            FakePassData(title: "Air Europa UX046", venue: "Carrasco Intl.", city: "Montevideo", passType: "flight", daysFromNow: 60, color: "rgb(0,94,184)",
                         origin: "Montevideo", destination: "Madrid", departTime: "23:55", seat: "14A",
                         latitude: -34.838, longitude: -56.030),
            FakePassData(title: "Hotel Riu Plaza España", venue: "Gran Vía 84", city: "Madrid", passType: "hotel", daysFromNow: 61, color: "rgb(140,90,20)",
                         latitude: 40.423, longitude: -3.712),
            FakePassData(title: "Museo Reina Sofía", venue: "Calle de Santa Isabel 52", city: "Madrid", passType: "museum", daysFromNow: 62, color: "rgb(165,0,0)",
                         latitude: 40.408, longitude: -3.694),
            FakePassData(title: "Air Europa UX045", venue: "Madrid–Barajas", city: "Madrid", passType: "flight", daysFromNow: 64, color: "rgb(0,94,184)",
                         origin: "Madrid", destination: "Montevideo", departTime: "12:10", seat: "9C",
                         latitude: 40.472, longitude: -3.561),
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
                latitude: data.latitude,
                longitude: data.longitude,
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
                eventUrls: nil,
                segment: data.origin == nil && data.destination == nil ? nil : PassSegment(
                    page: nil, label: nil, origin: data.origin, destination: data.destination,
                    departDate: nil, departTime: data.departTime, arriveDate: nil, arriveTime: nil,
                    carrier: nil, vehicleInfo: nil, seatInfo: data.seat, travelClass: nil,
                    confirmationNumber: nil, traveler: nil, notes: nil
                )
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
