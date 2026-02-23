import Foundation
import RevenueCat

@MainActor
class PassUsageManager: ObservableObject {
    static let shared = PassUsageManager()
    
    @Published var remainingPasses: Int = 0
    @Published var isLoadingBalance = false
    @Published var customerInfo: CustomerInfo?
    
    private init() {
        // Only use async streams for real-time updates
        
        // Subscribe to customer info updates which will trigger balance updates
        Task {
            for await customerInfo in Purchases.shared.customerInfoStream {
                await MainActor.run {
                    self.customerInfo = customerInfo
                    print("✅ Customer info updated via stream, refreshing balance...")
                }
                // Force refresh (with cache invalidation) to pick up virtual currency changes
                await forceRefreshBalance()
            }
        }
        
        // Fetch initial balance after a brief delay to ensure RevenueCat is ready
        Task {
            // Small delay to ensure RevenueCat SDK is fully initialized
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await refreshBalance()
        }
    }
    
    func canCreatePass() -> Bool {
        return remainingPasses > 0
    }
    
    func refreshBalance() async {
        isLoadingBalance = true
        defer { isLoadingBalance = false }
        
        do {
            // Fetch virtual currencies from RevenueCat
            let virtualCurrencies = try await Purchases.shared.virtualCurrencies()
            
            // Get PASS balance
            if let passBalance = virtualCurrencies.all["PASS"]?.balance {
                self.remainingPasses = passBalance
            } else {
                self.remainingPasses = 0
            }
            
            // Also update customer info
            self.customerInfo = try await Purchases.shared.customerInfo()
        } catch {
            print("Error fetching virtual currencies: \(error)")
            self.remainingPasses = 0
        }
    }
    
    // This will be called from server-side after successful pass generation
    func passGenerated() {
        // The server will handle the deduction via RevenueCat API
        // We just refresh the balance to show updated count
        Task {
            await refreshBalance()
        }
    }
    
    // Legacy method for compatibility - no longer used locally
    func consumePass() {
        // Do nothing - server handles this now
    }
    
    // Legacy method for compatibility - no longer used locally
    func addPasses(count: Int) {
        // Do nothing - RevenueCat handles this now
    }
    
    func purchasePassPack() {
        // This will be handled by PaywallView
        Task {
            await refreshBalance()
        }
    }
    
    /// Force an immediate balance refresh from RevenueCat
    func forceRefreshBalance() async {
        print("🔄 Force refreshing balance...")
        isLoadingBalance = true
        defer { isLoadingBalance = false }
        
        do {
            // Force fetch fresh data from RevenueCat
            Purchases.shared.invalidateCustomerInfoCache()
            
            // Fetch virtual currencies from RevenueCat
            let virtualCurrencies = try await Purchases.shared.virtualCurrencies()
            
            // Get PASS balance
            if let passBalance = virtualCurrencies.all["PASS"]?.balance {
                self.remainingPasses = passBalance
                print("✅ Force refresh complete: \(passBalance) passes")
            } else {
                self.remainingPasses = 0
                print("⚠️ Force refresh: No passes found")
            }
            
            // Also update customer info
            self.customerInfo = try await Purchases.shared.customerInfo()
        } catch {
            print("❌ Error force fetching virtual currencies: \(error)")
            self.remainingPasses = 0
        }
    }
}

