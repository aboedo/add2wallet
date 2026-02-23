import Foundation
import PassKit
import Combine

/// Pass Manager — handles adding passes to Apple Wallet
@MainActor
class PassManager: ObservableObject {
    @Published var isAuthorizedForBackgroundAdd = false
    
    init() {
        checkAuthorizationStatus()
    }
    
    func checkAuthorizationStatus() {
        #if !targetEnvironment(simulator)
        if #available(iOS 19.0, *) {
            let status = PKPassLibrary().authorizationStatus(for: .backgroundAddPasses)
            self.isAuthorizedForBackgroundAdd = (status == .authorized)
        }
        #endif
    }
    
    func requestBackgroundAddAuthorization() async -> Bool {
        #if !targetEnvironment(simulator)
        if #available(iOS 19.0, *) {
            do {
                let status = try await PKPassLibrary().requestAuthorization(for: .backgroundAddPasses)
                self.isAuthorizedForBackgroundAdd = (status == .authorized)
                return status == .authorized
            } catch {
                print("❌ Failed to request background add authorization: \(error)")
                return false
            }
        }
        #endif
        return false
    }
    
    func addPasses(_ passes: [PKPass]) async throws {
        #if !targetEnvironment(simulator)
        if #available(iOS 19.0, *), isAuthorizedForBackgroundAdd {
            await PKPassLibrary().addPasses(passes)
        } else {
            for pass in passes {
                if !PKPassLibrary().containsPass(pass) {
                    await PKPassLibrary().addPasses([pass])
                }
            }
        }
        #endif
    }
    
    func addPass(_ pass: PKPass) async throws {
        try await addPasses([pass])
    }
    
    func shouldPromptForBackgroundAuthorization() -> Bool {
        #if !targetEnvironment(simulator)
        if #available(iOS 19.0, *) {
            let status = PKPassLibrary().authorizationStatus(for: .backgroundAddPasses)
            return status == .notDetermined
        }
        #endif
        return false
    }
    
    func promptForBackgroundAuthorizationIfNeeded() async {
        if shouldPromptForBackgroundAuthorization() {
            _ = await requestBackgroundAddAuthorization()
        }
    }
}
