import Foundation
import PassKit
import Combine

/// iOS 26 Pass Manager with background add capability
@MainActor
class PassManager: ObservableObject {
    @Published var isAuthorizedForBackgroundAdd = false
    @Published var authorizationStatus: PKPassLibraryAddPassesStatus = .notDetermined
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        checkAuthorizationStatus()
    }
    
    /// Check current authorization status for background pass addition
    func checkAuthorizationStatus() {
        #if !targetEnvironment(simulator)
        if #available(iOS 19.0, *) {
            let status = PKPassLibrary().authorizationStatus(for: .backgroundAddPasses)
            self.authorizationStatus = status
            self.isAuthorizedForBackgroundAdd = (status == .authorized)
            print("📱 Background add authorization status: \(status.rawValue)")
        } else {
            // Fallback for older iOS versions
            self.authorizationStatus = .notDetermined
            self.isAuthorizedForBackgroundAdd = false
        }
        #else
        print("⚠️ Running on simulator - PKPassLibrary not available")
        #endif
    }
    
    /// Request authorization for background pass addition (iOS 26+)
    func requestBackgroundAddAuthorization() async -> Bool {
        #if !targetEnvironment(simulator)
        if #available(iOS 19.0, *) {
            do {
                let status = try await PKPassLibrary().requestAuthorization(for: .backgroundAddPasses)
                await MainActor.run {
                    self.authorizationStatus = status
                    self.isAuthorizedForBackgroundAdd = (status == .authorized)
                }
                print("✅ Background add authorization granted: \(status == .authorized)")
                return status == .authorized
            } catch {
                print("❌ Failed to request background add authorization: \(error)")
                return false
            }
        } else {
            print("⚠️ Background add requires iOS 19.0+")
            return false
        }
        #else
        print("⚠️ Running on simulator - cannot request authorization")
        return false
        #endif
    }
    
    /// Add passes to Wallet with automatic or manual flow based on authorization
    func addPasses(_ passes: [PKPass]) async throws {
        #if !targetEnvironment(simulator)
        if #available(iOS 19.0, *) {
            if isAuthorizedForBackgroundAdd {
                // Add passes in background without prompts
                PKPassLibrary().addPasses(passes)
                print("🎫 Added \(passes.count) pass(es) automatically in background")
            } else {
                // Fall back to traditional add method with user confirmation
                for pass in passes {
                    if PKPassLibrary().containsPass(pass) {
                        print("⚠️ Pass already exists in Wallet")
                    } else {
                        PKPassLibrary().addPasses([pass])
                    }
                }
            }
        } else {
            // Pre-iOS 19 fallback
            for pass in passes {
                if !PKPassLibrary().containsPass(pass) {
                    PKPassLibrary().addPasses([pass])
                }
            }
        }
        #else
        print("⚠️ Running on simulator - cannot add passes")
        #endif
    }
    
    /// Add a single pass with automatic background addition if authorized
    func addPass(_ pass: PKPass) async throws {
        try await addPasses([pass])
    }
    
    /// Check if we should prompt for background authorization
    /// Best to do this after the user successfully adds their first pass
    func shouldPromptForBackgroundAuthorization() -> Bool {
        #if !targetEnvironment(simulator)
        if #available(iOS 19.0, *) {
            return authorizationStatus == .notDetermined
        }
        #endif
        return false
    }
    
    /// Prompt for background authorization after successful pass addition
    func promptForBackgroundAuthorizationIfNeeded() async {
        if shouldPromptForBackgroundAuthorization() {
            _ = await requestBackgroundAddAuthorization()
        }
    }
}

// Extension for PKPassLibraryAddPassesStatus compatibility
@available(iOS 19.0, *)
extension PKPassLibraryAddPassesStatus {
    var displayName: String {
        switch self {
        case .notDetermined:
            return "Not Determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        @unknown default:
            return "Unknown"
        }
    }
}