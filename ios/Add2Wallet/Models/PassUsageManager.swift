import Foundation
import RevenueCat

@MainActor
class PassUsageManager: NSObject, ObservableObject {
    static let shared = PassUsageManager()

    @Published var remainingPasses: Int = 0
    @Published var isLoadingBalance = false
    @Published var customerInfo: CustomerInfo?

    private override init() {
        super.init()

        // Set ourselves as the RevenueCat delegate for live customerInfo updates
        Purchases.shared.delegate = self

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
        // Use retry since server may not have deducted yet when we check
        let currentBalance = remainingPasses
        Task {
            await forceRefreshBalanceWithRetry(previousBalance: currentBalance)
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
            
            // Fetch fresh customer info first (triggers server sync)
            self.customerInfo = try await Purchases.shared.customerInfo()
            
            // Then fetch virtual currencies
            let virtualCurrencies = try await Purchases.shared.virtualCurrencies()
            
            // Get PASS balance
            if let passBalance = virtualCurrencies.all["PASS"]?.balance {
                self.remainingPasses = passBalance
                print("✅ Force refresh complete: \(passBalance) passes")
            } else {
                self.remainingPasses = 0
                print("⚠️ Force refresh: No passes found")
            }
            
        } catch {
            print("❌ Error force fetching virtual currencies: \(error)")
            self.remainingPasses = 0
        }
    }
    
    /// Force refresh with retry — use after purchases where server may need time to process
    func forceRefreshBalanceWithRetry(previousBalance: Int, maxRetries: Int = 3) async {
        print("🔄 Force refresh with retry (previous balance: \(previousBalance))...")

        for attempt in 1...maxRetries {
            // Exponential backoff: 1s, 2s, 4s
            let delayNanos = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
            try? await Task.sleep(nanoseconds: delayNanos)

            await forceRefreshBalance()

            if remainingPasses != previousBalance {
                print("✅ Balance updated after attempt \(attempt): \(previousBalance) → \(remainingPasses)")
                return
            }
            print("⏳ Attempt \(attempt): balance still \(remainingPasses), retrying...")
        }
        print("⚠️ Balance didn't change after \(maxRetries) retries")
    }
}

// MARK: - PurchasesDelegate

extension PassUsageManager: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.customerInfo = customerInfo
            print("✅ Customer info updated via delegate, refreshing balance...")
            await self.forceRefreshBalance()
        }
    }
}

