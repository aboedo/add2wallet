import Foundation
import RevenueCat
@testable import Add2Wallet

// MARK: - Mock RevenueCat Components

class MockPurchases {
    static var shared = MockPurchases()
    
    var mockAppUserID: String = "test-user-123"
    var mockCustomerInfo: CustomerInfo?
    var mockVirtualCurrencies: VirtualCurrencies?
    var shouldThrowError = false
    var mockError: Error = MockRevenueCatError.unknownError
    
    // MARK: - Mock Properties
    
    var appUserID: String {
        return mockAppUserID
    }
    
    // MARK: - Mock Methods
    
    func customerInfo() async throws -> CustomerInfo {
        if shouldThrowError {
            throw mockError
        }
        
        guard let customerInfo = mockCustomerInfo else {
            // Create a default mock CustomerInfo
            return createMockCustomerInfo()
        }
        
        return customerInfo
    }
    
    func virtualCurrencies() async throws -> VirtualCurrencies {
        if shouldThrowError {
            throw mockError
        }
        
        return mockVirtualCurrencies ?? createMockVirtualCurrencies()
    }
    
    func syncPurchases() async throws -> CustomerInfo {
        if shouldThrowError {
            throw mockError
        }
        
        return mockCustomerInfo ?? createMockCustomerInfo()
    }
    
    // MARK: - Configuration Methods
    
    func setMockCustomerInfo(_ customerInfo: CustomerInfo) {
        mockCustomerInfo = customerInfo
    }
    
    func setMockVirtualCurrencies(_ currencies: VirtualCurrencies) {
        mockVirtualCurrencies = currencies
    }
    
    func setMockError(_ error: Error) {
        mockError = error
        shouldThrowError = true
    }
    
    func clearError() {
        shouldThrowError = false
    }
    
    func reset() {
        mockAppUserID = "test-user-123"
        mockCustomerInfo = nil
        mockVirtualCurrencies = nil
        shouldThrowError = false
        mockError = MockRevenueCatError.unknownError
    }
    
    // MARK: - Helper Methods
    
    private func createMockCustomerInfo() -> CustomerInfo {
        // Note: CustomerInfo is a complex RevenueCat object that's difficult to mock directly
        // In a real implementation, you might need to use dependency injection
        // For now, we'll create a minimal mock or use a protocol
        fatalError("CustomerInfo mocking requires more complex setup - consider using protocols")
    }
    
    private func createMockVirtualCurrencies() -> VirtualCurrencies {
        // Similar issue with VirtualCurrencies
        fatalError("VirtualCurrencies mocking requires more complex setup - consider using protocols")
    }
}

// MARK: - Mock PassUsageManager

class MockPassUsageManager: ObservableObject {
    @Published var remainingPasses: Int = 10
    @Published var isLoadingBalance = false
    @Published var customerInfo: CustomerInfo?
    
    private var shouldThrowError = false
    private var mockError: Error = MockRevenueCatError.unknownError
    
    func canCreatePass() -> Bool {
        return remainingPasses > 0
    }
    
    func refreshBalance() async {
        isLoadingBalance = true
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        if shouldThrowError {
            remainingPasses = 0
        }
        
        isLoadingBalance = false
    }
    
    func passGenerated() {
        if remainingPasses > 0 {
            remainingPasses -= 1
        }
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
        // Mock purchase completion
        addPasses(count: 10)
    }
    
    // MARK: - Test Configuration
    
    func setRemainingPasses(_ count: Int) {
        remainingPasses = count
    }
    
    func setError(_ error: Error) {
        shouldThrowError = true
        mockError = error
    }
    
    func clearError() {
        shouldThrowError = false
    }
    
    func reset() {
        remainingPasses = 10
        isLoadingBalance = false
        customerInfo = nil
        shouldThrowError = false
        mockError = MockRevenueCatError.unknownError
    }
}

// MARK: - Protocol-Based Approach for Better Testability
// Note: For testing, use MockPassUsageManager directly instead of a protocol
// to avoid MainActor isolation issues

// MARK: - Mock Errors

enum MockRevenueCatError: Error, LocalizedError {
    case networkError
    case invalidUser
    case purchaseError
    case unknownError
    case balanceUnavailable
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Mock network error"
        case .invalidUser:
            return "Mock invalid user error"
        case .purchaseError:
            return "Mock purchase error"
        case .unknownError:
            return "Mock unknown error"
        case .balanceUnavailable:
            return "Mock balance unavailable error"
        }
    }
}

// MARK: - Test Configuration Helpers

extension MockPassUsageManager {
    
    func configureForNoPassesRemaining() {
        setRemainingPasses(0)
    }
    
    func configureForNetworkError() {
        setError(MockRevenueCatError.networkError)
    }
    
    func configureForPurchaseSuccess() {
        setRemainingPasses(10)
        clearError()
    }
    
    func configureForBalanceError() {
        setError(MockRevenueCatError.balanceUnavailable)
    }
}