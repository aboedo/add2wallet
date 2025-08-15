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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .tint(ThemeManager.Colors.brandPrimary)
                .onOpenURL { url in
                    handleURL(url)
                }
                .onAppear {
                    // Check if this is a fresh install and sync purchases
                    Task {
                        await syncPurchasesOnFreshInstall()
                    }
                    
                    checkForSharedPDF()
                }
        }
    }
    
    private func handleURL(_ url: URL) {
        print("🟢 App: handleURL called with: \(url)")
        print("🟢 App: URL scheme: \(url.scheme ?? "nil"), host: \(url.host ?? "nil")")
        print("🟢 App: URL path: \(url.path), isFileURL: \(url.isFileURL)")
        
        // Handle Universal Links for sharing (links.add2wallet.app/share/token)
        if url.host == "links.add2wallet.app" && url.pathComponents.count >= 3 && url.pathComponents[1] == "share" {
            let token = url.pathComponents[2]
            print("🟢 App: Handling Universal Link with token: \(token)")
            handleSharedPDFWithToken(token: token)
            return
        }
        
        // Handle custom URL scheme sharing (add2wallet://share/token)
        if url.scheme == "add2wallet" && url.host == "share" && url.pathComponents.count >= 2 {
            let token = url.pathComponents[1]
            print("🟢 App: Handling custom URL scheme with token: \(token)")
            handleSharedPDFWithToken(token: token)
            return
        }
        
        // Legacy support for old share-pdf scheme
        if url.scheme == "add2wallet" && url.host == "share-pdf" {
            print("🟢 App: Handling legacy share-pdf scheme")
            checkForSharedPDF()
            return
        }
        
        // Handle files opened via "Open in Add2Wallet"
        if url.isFileURL {
            print("🟢 App: Handling file URL: \(url)")
            
            // Request access to security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                print("🔴 App: Failed to start accessing security scoped resource")
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
                print("🟢 App: Stopped accessing security scoped resource")
            }
            
            do {
                let data = try Data(contentsOf: url)
                let filename = url.lastPathComponent
                print("🟢 App: Successfully loaded file data (\(data.count) bytes) for: \(filename)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("SharedPDFReceived"),
                    object: nil,
                    userInfo: ["filename": filename, "data": data]
                )
                print("🟢 App: Posted SharedPDFReceived notification")
            } catch {
                print("🔴 App: Error loading file: \(error)")
            }
        } else {
            print("🟡 App: URL not handled - not a file URL or recognized scheme")
        }
    }
    
    private func handleSharedPDFWithToken(token: String) {
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.andresboedo.add2wallet") else {
            return
        }
        
        // Look for token-specific directory
        let tokenDir = sharedContainer.appendingPathComponent("shared").appendingPathComponent(token)
        let metadataFile = tokenDir.appendingPathComponent("metadata.json")
        let pdfFile = tokenDir.appendingPathComponent("document.pdf")
        
        if FileManager.default.fileExists(atPath: metadataFile.path),
           FileManager.default.fileExists(atPath: pdfFile.path) {
            do {
                // Read metadata
                let metadataData = try Data(contentsOf: metadataFile)
                let metadata = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any]
                let filename = metadata?["filename"] as? String ?? "shared_document.pdf"
                
                // Read PDF data
                let pdfData = try Data(contentsOf: pdfFile)
                
                // Process the shared PDF
                NotificationCenter.default.post(
                    name: NSNotification.Name("SharedPDFReceived"),
                    object: nil,
                    userInfo: ["filename": filename, "data": pdfData]
                )
                
                // Clean up the token directory
                try? FileManager.default.removeItem(at: tokenDir)
            } catch {
                // Silent error handling
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
    
    private func checkForSharedPDF() {
        // Legacy support for old file-based sharing
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.andresboedo.add2wallet") else {
            return
        }
        
        let sharedFile = sharedContainer.appendingPathComponent("shared_pdf.json")
        let pdfFile = sharedContainer.appendingPathComponent("shared.pdf")

        if FileManager.default.fileExists(atPath: sharedFile.path),
           FileManager.default.fileExists(atPath: pdfFile.path) {
            do {
                let jsonData = try Data(contentsOf: sharedFile)
                if let sharedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let filename = sharedData["filename"] as? String {
                    let pdfData = try Data(contentsOf: pdfFile)
                    
                    // Process the shared PDF
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SharedPDFReceived"),
                        object: nil,
                        userInfo: ["filename": filename, "data": pdfData]
                    )
                    
                    // Clean up the shared file
                    try? FileManager.default.removeItem(at: sharedFile)
                    try? FileManager.default.removeItem(at: pdfFile)
                }
            } catch {
                // Silent error handling
            }
        }
    }
}
