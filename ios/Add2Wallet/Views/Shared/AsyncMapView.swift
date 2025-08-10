import SwiftUI
import MapKit
import CoreLocation

struct MapAnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let title: String
}

struct AsyncMapView: View {
    let metadata: EnhancedPassMetadata
    @Environment(\.openURL) private var openURL
    
    @State private var coordinateFromAddress: CLLocationCoordinate2D?
    @State private var isLoadingCoordinate = false
    
    private var shouldShowMap: Bool {
        return hasAddress || hasCoordinates
    }
    
    private var hasAddress: Bool {
        return metadata.venueAddress?.isEmpty == false
    }
    
    private var hasCoordinates: Bool {
        return metadata.latitude != nil && metadata.longitude != nil
    }
    
    private var finalCoordinate: CLLocationCoordinate2D? {
        // Prefer geocoded address coordinate, fallback to GPS coordinates
        if let coord = coordinateFromAddress {
            return coord
        } else if let lat = metadata.latitude, let lon = metadata.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }
    
    private var mapRegion: MKCoordinateRegion {
        guard let coord = finalCoordinate else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), latitudinalMeters: 10000, longitudinalMeters: 10000)
        }
        // Zoom out more for better context - increased from default ~1000m to 3000m
        return MKCoordinateRegion(center: coord, latitudinalMeters: 3000, longitudinalMeters: 3000)
    }
    
    var body: some View {
        Group {
            if shouldShowMap {
                VStack(spacing: 8) {
                    if isLoadingCoordinate {
                        // Loading state
                        loadingMapView
                    } else {
                        // Map with coordinate
                        mapView
                    }
                    
                    // Map action buttons
                    if finalCoordinate != nil {
                        mapActionButtons
                    }
                }
            }
        }
        .onAppear {
            geocodeAddressIfNeeded()
        }
    }
    
    private var loadingMapView: some View {
        VStack(spacing: 12) {
            SwiftUI.ProgressView()
                .scaleEffect(1.2)
            Text("Loading map...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3))
        )
    }
    
    private var mapView: some View {
        Map(coordinateRegion: .constant(mapRegion), 
            annotationItems: finalCoordinate != nil ? [MapAnnotationItem(coordinate: finalCoordinate!, title: metadata.venueName ?? "Location")] : []) { annotation in
            MapPin(coordinate: annotation.coordinate, tint: .red)
        }
        .mapStyle(.standard)
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3))
        )
    }
    
    private var mapActionButtons: some View {
        HStack(spacing: 8) {
            Button {
                if let coord = finalCoordinate {
                    openInAppleMaps(coordinate: coord, name: metadata.venueName ?? "Location")
                }
            } label: {
                Label("Open in Apple Maps", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                if let coord = finalCoordinate {
                    openInGoogleMaps(coordinate: coord, name: metadata.venueName ?? "Location")
                }
            } label: {
                Label("Open in Google Maps", systemImage: "map.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .font(.footnote)
        .padding(.top, 6)
    }
    
    private func geocodeAddressIfNeeded() {
        // Only geocode if we have an address and don't already have coordinates
        guard coordinateFromAddress == nil,
              !hasCoordinates,
              let address = metadata.venueAddress,
              !address.isEmpty else {
            return
        }
        
        isLoadingCoordinate = true
        
        Task {
            await performGeocoding(for: address)
        }
    }
    
    private func performGeocoding(for address: String) async {
        let geocoder = CLGeocoder()
        
        // Build full address string
        var fullAddress = address
        if let city = metadata.city, !city.isEmpty {
            fullAddress += ", " + city
        }
        if let stateCountry = metadata.stateCountry, !stateCountry.isEmpty {
            fullAddress += ", " + stateCountry
        }
        
        do {
            let placemarks = try await geocoder.geocodeAddressString(fullAddress)
            
            if let placemark = placemarks.first,
               let location = placemark.location {
                await MainActor.run {
                    coordinateFromAddress = location.coordinate
                    isLoadingCoordinate = false
                }
            } else {
                await MainActor.run {
                    isLoadingCoordinate = false
                }
            }
        } catch {
            print("Geocoding error: \(error)")
            await MainActor.run {
                isLoadingCoordinate = false
            }
        }
    }

    private func openInAppleMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Location"
        if let url = URL(string: "http://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=\(query)") {
            openURL(url)
        }
    }

    private func openInGoogleMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Location"
        let appURL = URL(string: "comgooglemaps://?q=\(query)&center=\(coordinate.latitude),\(coordinate.longitude)&zoom=16")
        let webURL = URL(string: "https://maps.google.com/?q=\(query)&ll=\(coordinate.latitude),\(coordinate.longitude)&z=16")

        if let appURL = appURL {
            openURL(appURL) { accepted in
                if !accepted, let webURL = webURL {
                    openURL(webURL)
                }
            }
        } else if let webURL = webURL {
            openURL(webURL)
        }
    }
}

#Preview {
    let sampleMetadata = EnhancedPassMetadata(
        eventType: "Concert",
        eventName: "Taylor Swift Concert",
        title: "Taylor Swift Eras Tour",
        description: "The most spectacular concert of the year",
        date: "2024-12-15",
        time: "20:00",
        duration: "3 hours",
        venueName: "Madison Square Garden",
        venueAddress: "4 Pennsylvania Plaza",
        city: "New York",
        stateCountry: "NY, USA",
        latitude: nil, // Test async geocoding
        longitude: nil,
        organizer: "Live Nation",
        performerArtist: "Taylor Swift",
        seatInfo: "Section 100, Row A, Seat 15",
        barcodeData: "123456789",
        price: "$150.00",
        confirmationNumber: "ABC123XYZ",
        gateInfo: "Gate 7",
        eventDescription: "Experience the magic of Taylor Swift's Eras Tour",
        venueType: "Arena",
        capacity: "20,000",
        website: "msg.com",
        phone: "(212) 465-6741",
        nearbyLandmarks: ["Empire State Building", "Herald Square"],
        publicTransport: "Penn Station (1, 2, 3, A, C, E trains)",
        parkingInfo: "$40 event parking available",
        ageRestriction: "All ages",
        dressCode: "Casual",
        weatherConsiderations: "Indoor venue",
        amenities: ["Concessions", "Gift Shop", "Accessible Seating"],
        accessibility: "ADA compliant",
        aiProcessed: true,
        confidenceScore: 95,
        processingTimestamp: "2024-01-01T12:00:00Z",
        modelUsed: "gpt-4",
        enrichmentCompleted: true,
        backgroundColor: "rgb(138,43,226)",
        foregroundColor: "rgb(255,255,255)",
        labelColor: "rgb(255,255,255)"
    )
    
    AsyncMapView(metadata: sampleMetadata)
        .padding()
}