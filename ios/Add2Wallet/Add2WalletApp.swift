import SwiftUI
import SwiftData

@main
struct Add2WalletApp: App {
    // UIApplicationDelegateAdaptor temporarily disabled; not required for URL
    // @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    let container: ModelContainer
    
    init() {
        do {
            container = try ModelContainer(for: SavedPass.self)
        } catch {
            fatalError("Failed to initialize Swift Data container: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .onOpenURL { url in
                    handleURL(url)
                }
                .onAppear {
                    
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
