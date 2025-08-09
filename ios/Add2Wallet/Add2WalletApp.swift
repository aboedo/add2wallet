import SwiftUI

@main
struct Add2WalletApp: App {
    // UIApplicationDelegateAdaptor temporarily disabled; not required for URL
    // @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleURL(url)
                }
                .onAppear {
                    checkForSharedPDF()
                }
        }
    }
    
    private func handleURL(_ url: URL) {
        // Handle Universal Links for sharing (links.add2wallet.app/share/token)
        if url.host == "links.add2wallet.app" && url.pathComponents.count >= 3 && url.pathComponents[1] == "share" {
            let token = url.pathComponents[2]
            handleSharedPDFWithToken(token: token)
            return
        }
        
        // Handle custom URL scheme sharing (add2wallet://share/token)
        if url.scheme == "add2wallet" && url.host == "share" && url.pathComponents.count >= 2 {
            let token = url.pathComponents[1]
            handleSharedPDFWithToken(token: token)
            return
        }
        
        // Legacy support for old share-pdf scheme
        if url.scheme == "add2wallet" && url.host == "share-pdf" {
            checkForSharedPDF()
            return
        }
        
        // Handle files opened via "Open in Add2Wallet"
        if url.isFileURL {
            do {
                let data = try Data(contentsOf: url)
                let filename = url.lastPathComponent
                NotificationCenter.default.post(
                    name: NSNotification.Name("SharedPDFReceived"),
                    object: nil,
                    userInfo: ["filename": filename, "data": data]
                )
            } catch {
                // ignore in UI for now
            }
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