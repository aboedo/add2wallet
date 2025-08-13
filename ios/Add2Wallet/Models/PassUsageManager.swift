import Foundation

class PassUsageManager: ObservableObject {
    static let shared = PassUsageManager()
    
    private let passCountKey = "remainingPassCount"
    private let defaults = UserDefaults.standard
    
    @Published var remainingPasses: Int {
        didSet {
            defaults.set(remainingPasses, forKey: passCountKey)
        }
    }
    
    private init() {
        // Initialize with 0 passes on first launch
        self.remainingPasses = defaults.integer(forKey: passCountKey)
    }
    
    func canCreatePass() -> Bool {
        return remainingPasses > 0
    }
    
    func consumePass() {
        if remainingPasses > 0 {
            remainingPasses -= 1
        }
    }
    
    func addPasses(count: Int) {
        remainingPasses += count
    }
    
    func purchasePassPack() {
        // Simple implementation: adds 10 passes
        addPasses(count: 10)
    }
}