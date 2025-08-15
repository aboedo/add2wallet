import XCTest
import Combine
import RevenueCat
@testable import Add2Wallet

@MainActor
class PassUsageManagerTests: XCTestCase {
    var mockUsageManager: MockPassUsageManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockUsageManager = MockPassUsageManager()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables = nil
        mockUsageManager = nil
        super.tearDown()
    }
    
    // MARK: - Basic Functionality Tests
    
    func testInitialState() {
        XCTAssertEqual(mockUsageManager.remainingPasses, 10)
        XCTAssertFalse(mockUsageManager.isLoadingBalance)
        XCTAssertNil(mockUsageManager.customerInfo)
    }
    
    func testCanCreatePassWithRemainingPasses() {
        mockUsageManager.setRemainingPasses(5)
        XCTAssertTrue(mockUsageManager.canCreatePass())
    }
    
    func testCanCreatePassWithNoPasses() {
        mockUsageManager.setRemainingPasses(0)
        XCTAssertFalse(mockUsageManager.canCreatePass())
    }
    
    func testPassGenerated() {
        let initialCount = mockUsageManager.remainingPasses
        mockUsageManager.passGenerated()
        XCTAssertEqual(mockUsageManager.remainingPasses, initialCount - 1)
    }
    
    func testPassGeneratedWhenNoPasses() {
        mockUsageManager.setRemainingPasses(0)
        mockUsageManager.passGenerated()
        XCTAssertEqual(mockUsageManager.remainingPasses, 0) // Should not go negative
    }
    
    func testConsumePass() {
        let initialCount = mockUsageManager.remainingPasses
        mockUsageManager.consumePass()
        XCTAssertEqual(mockUsageManager.remainingPasses, initialCount - 1)
    }
    
    func testConsumePassWhenNoPasses() {
        mockUsageManager.setRemainingPasses(0)
        mockUsageManager.consumePass()
        XCTAssertEqual(mockUsageManager.remainingPasses, 0) // Should not go negative
    }
    
    func testAddPasses() {
        let initialCount = mockUsageManager.remainingPasses
        mockUsageManager.addPasses(count: 5)
        XCTAssertEqual(mockUsageManager.remainingPasses, initialCount + 5)
    }
    
    func testPurchasePassPack() {
        let initialCount = mockUsageManager.remainingPasses
        mockUsageManager.purchasePassPack()
        XCTAssertEqual(mockUsageManager.remainingPasses, initialCount + 10)
    }
    
    // MARK: - Async Balance Refresh Tests
    
    func testRefreshBalanceSuccess() async {
        // Set up expectation for loading state changes
        let loadingExpectation = XCTestExpectation(description: "Loading state change")
        loadingExpectation.expectedFulfillmentCount = 2 // Start and end loading
        
        mockUsageManager.$isLoadingBalance
            .sink { isLoading in
                if isLoading {
                    loadingExpectation.fulfill()
                } else {
                    // Only fulfill when loading stops
                    loadingExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        await mockUsageManager.refreshBalance()
        
        await fulfillment(of: [loadingExpectation], timeout: 2.0)
        XCTAssertFalse(mockUsageManager.isLoadingBalance)
    }
    
    func testRefreshBalanceWithError() async {
        mockUsageManager.configureForNetworkError()
        
        let initialPasses = mockUsageManager.remainingPasses
        await mockUsageManager.refreshBalance()
        
        // Error case should set passes to 0
        XCTAssertEqual(mockUsageManager.remainingPasses, 0)
        XCTAssertFalse(mockUsageManager.isLoadingBalance)
    }
    
    // MARK: - State Management Tests
    
    func testReset() {
        // Modify state
        mockUsageManager.setRemainingPasses(5)
        mockUsageManager.setError(MockRevenueCatError.networkError)
        
        // Reset
        mockUsageManager.reset()
        
        // Verify reset state
        XCTAssertEqual(mockUsageManager.remainingPasses, 10)
        XCTAssertFalse(mockUsageManager.isLoadingBalance)
        XCTAssertNil(mockUsageManager.customerInfo)
    }
    
    // MARK: - Configuration Helper Tests
    
    func testConfigureForNoPassesRemaining() {
        mockUsageManager.configureForNoPassesRemaining()
        XCTAssertEqual(mockUsageManager.remainingPasses, 0)
        XCTAssertFalse(mockUsageManager.canCreatePass())
    }
    
    func testConfigureForPurchaseSuccess() {
        mockUsageManager.configureForPurchaseSuccess()
        XCTAssertEqual(mockUsageManager.remainingPasses, 10)
        XCTAssertTrue(mockUsageManager.canCreatePass())
    }
    
    func testConfigureForBalanceError() {
        mockUsageManager.configureForBalanceError()
        // Balance refresh should handle the error gracefully
    }
    
    // MARK: - Edge Cases
    
    func testMultiplePassGenerations() {
        mockUsageManager.setRemainingPasses(3)
        
        // Generate multiple passes
        mockUsageManager.passGenerated()
        XCTAssertEqual(mockUsageManager.remainingPasses, 2)
        
        mockUsageManager.passGenerated()
        XCTAssertEqual(mockUsageManager.remainingPasses, 1)
        
        mockUsageManager.passGenerated()
        XCTAssertEqual(mockUsageManager.remainingPasses, 0)
        
        // Should not go negative
        mockUsageManager.passGenerated()
        XCTAssertEqual(mockUsageManager.remainingPasses, 0)
    }
    
    func testBoundaryConditions() {
        // Test with 1 pass remaining
        mockUsageManager.setRemainingPasses(1)
        XCTAssertTrue(mockUsageManager.canCreatePass())
        
        mockUsageManager.passGenerated()
        XCTAssertFalse(mockUsageManager.canCreatePass())
        XCTAssertEqual(mockUsageManager.remainingPasses, 0)
    }
    
    func testLargePassCounts() {
        // Test with large number of passes
        mockUsageManager.setRemainingPasses(1000)
        XCTAssertTrue(mockUsageManager.canCreatePass())
        
        mockUsageManager.addPasses(count: 500)
        XCTAssertEqual(mockUsageManager.remainingPasses, 1500)
        
        // Consume many passes
        for _ in 0..<100 {
            mockUsageManager.consumePass()
        }
        XCTAssertEqual(mockUsageManager.remainingPasses, 1400)
    }
    
    // MARK: - Observable Object Tests
    
    func testPublishedPropertyChanges() {
        let remainingPassesExpectation = XCTestExpectation(description: "Remaining passes change")
        let loadingExpectation = XCTestExpectation(description: "Loading state change")
        
        // Monitor remainingPasses changes
        mockUsageManager.$remainingPasses
            .dropFirst() // Skip initial value
            .sink { count in
                if count == 5 {
                    remainingPassesExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Monitor isLoadingBalance changes
        mockUsageManager.$isLoadingBalance
            .dropFirst() // Skip initial value
            .sink { isLoading in
                if isLoading {
                    loadingExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Trigger changes
        mockUsageManager.setRemainingPasses(5)
        
        Task {
            await mockUsageManager.refreshBalance()
        }
        
        wait(for: [remainingPassesExpectation, loadingExpectation], timeout: 2.0)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorPropagation() async {
        // Test that errors are handled gracefully
        mockUsageManager.setError(MockRevenueCatError.balanceUnavailable)
        
        await mockUsageManager.refreshBalance()
        
        // Should not crash and should set passes to 0
        XCTAssertEqual(mockUsageManager.remainingPasses, 0)
    }
    
    func testRecoveryFromError() {
        // Set error state
        mockUsageManager.configureForBalanceError()
        
        // Clear error and test recovery
        mockUsageManager.clearError()
        mockUsageManager.configureForPurchaseSuccess()
        
        XCTAssertEqual(mockUsageManager.remainingPasses, 10)
        XCTAssertTrue(mockUsageManager.canCreatePass())
    }
}

// MARK: - Mock RevenueCat Error Tests

class MockRevenueCatErrorTests: XCTestCase {
    
    func testMockErrorTypes() {
        let networkError = MockRevenueCatError.networkError
        XCTAssertEqual(networkError.errorDescription, "Mock network error")
        
        let invalidUserError = MockRevenueCatError.invalidUser
        XCTAssertEqual(invalidUserError.errorDescription, "Mock invalid user error")
        
        let purchaseError = MockRevenueCatError.purchaseError
        XCTAssertEqual(purchaseError.errorDescription, "Mock purchase error")
        
        let unknownError = MockRevenueCatError.unknownError
        XCTAssertEqual(unknownError.errorDescription, "Mock unknown error")
        
        let balanceUnavailableError = MockRevenueCatError.balanceUnavailable
        XCTAssertEqual(balanceUnavailableError.errorDescription, "Mock balance unavailable error")
    }
    
    func testErrorEquality() {
        let error1 = MockRevenueCatError.networkError
        let error2 = MockRevenueCatError.networkError
        
        // Test that error descriptions are consistent
        XCTAssertEqual(error1.errorDescription, error2.errorDescription)
    }
}