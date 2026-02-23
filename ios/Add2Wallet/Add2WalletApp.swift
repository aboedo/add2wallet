import SwiftUI
import SwiftData
import RevenueCat

@main
struct Add2WalletApp: App {
    // UIApplicationDelegateAdaptor temporarily disabled; not required for URL
    // @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    let container: ModelContainer
    
    init() {
        // Initialize RevenueCat
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .info
        #endif
        Purchases.configure(withAPIKey: "appl_fYlYmWylgRwabkYEZoocYZaCOGU")
        
        // Initialize PassUsageManager early to set up delegate and fetch initial balance
        _ = PassUsageManager.shared
        
        #if DEBUG
        // Initialize debug shake detector
        _ = DebugShakeDetector.shared
        #endif
        
        do {
            // Create a schema with the current model
            let schema = Schema([SavedPass.self])
            
            // Configure with iCloud sync enabled
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                cloudKitDatabase: .private("iCloud.com.andresboedo.add2wallet")
            )
            
            // First, try to create the container normally
            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("✅ Successfully created SwiftData container with CloudKit sync enabled")
                print("📱 CloudKit container: iCloud.com.andresboedo.add2wallet")
            } catch {
                print("SwiftData container creation error: \(error)")
                
                // Check if this is a CloudKit-related error before deleting stores
                let errorDescription = error.localizedDescription.lowercased()
                let isCloudKitError = errorDescription.contains("cloudkit") || 
                                    errorDescription.contains("icloud") ||
                                    errorDescription.contains("ckrecord") ||
                                    errorDescription.contains("core data error") ||
                                    errorDescription.contains("134060")
                
                if isCloudKitError {
                    print("CloudKit error detected - preserving local store, creating without CloudKit")
                    // Try creating without CloudKit as fallback
                    let fallbackConfig = ModelConfiguration(
                        schema: schema,
                        isStoredInMemoryOnly: false,
                        allowsSave: true,
                        cloudKitDatabase: .none
                    )
                    container = try ModelContainer(for: schema, configurations: [fallbackConfig])
                    print("Created fallback container without CloudKit sync")
                } else {
                    print("Migration error detected, attempting store cleanup: \(error)")
                    
                    // Find and remove all possible store locations (but preserve CloudKit metadata)
                    let appSupportURL = URL.applicationSupportDirectory
                    let storeURL = appSupportURL.appendingPathComponent("default.store")
                    
                    // Also check in App Group container if it exists
                    if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.andresboedo.add2wallet") {
                        let groupStoreURL = groupURL.appendingPathComponent("Library/Application Support/default.store")
                        try? FileManager.default.removeItem(at: groupStoreURL)
                        try? FileManager.default.removeItem(at: groupStoreURL.appendingPathExtension("shm"))
                        try? FileManager.default.removeItem(at: groupStoreURL.appendingPathExtension("wal"))
                    }
                    
                    // Remove main store files but NOT CloudKit cache
                    try? FileManager.default.removeItem(at: storeURL)
                    try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
                    try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
                    
                    // Try again with a fresh store
                    container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                    print("Successfully created new store after dropping old data")
                }
            }
        } catch {
            fatalError("Failed to initialize Swift Data container: \(error)")
        }
    }
    
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .tint(ThemeManager.Colors.brandPrimary)
                .onOpenURL { url in
                    URLHandler.handleURL(url)
                }
                .onAppear {
                    // Check if this is a fresh install and sync purchases
                    Task {
                        await syncPurchasesOnFreshInstall()
                    }
                    
                    URLHandler.checkForSharedPDF()
                    URLHandler.checkForPendingShareToken()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                URLHandler.checkForPendingShareToken()
                // Refresh balance when app comes to foreground
                Task {
                    await PassUsageManager.shared.forceRefreshBalance()
                }
            }
        }
    }
    
    private func syncPurchasesOnFreshInstall() async {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "HasLaunchedBefore")
        
        if !hasLaunchedBefore {
            print("🔄 Fresh install detected, syncing purchases with RevenueCat")
            do {
                let customerInfo = try await Purchases.shared.syncPurchases()
                print("✅ Successfully synced purchases on fresh install")
                print("📊 Customer ID: \(customerInfo.originalAppUserId)")
                
                // Update PassUsageManager with the synced customer info
                await MainActor.run {
                    PassUsageManager.shared.customerInfo = customerInfo
                }
                
                // Refresh the balance to update UI
                await PassUsageManager.shared.refreshBalance()
                print("💰 Balance refreshed after sync")
                
            } catch {
                print("❌ Failed to sync purchases on fresh install: \(error)")
            }
            
            // Mark that the app has launched before
            UserDefaults.standard.set(true, forKey: "HasLaunchedBefore")
        } else {
            // Even on non-fresh installs, ensure we have the latest customer info
            print("🔄 Regular launch, refreshing customer info and balance")
            await PassUsageManager.shared.refreshBalance()
        }
    }
    
}
