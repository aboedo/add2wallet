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
    
    private func checkForSharedPDF() {
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