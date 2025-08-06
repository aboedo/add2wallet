import SwiftUI

@main
struct Add2WalletApp: App {
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
        }
    }
    
    private func checkForSharedPDF() {
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.andresboedo.add2wallet") else {
            return
        }
        
        let sharedFile = sharedContainer.appendingPathComponent("shared_pdf.json")
        
        if FileManager.default.fileExists(atPath: sharedFile.path) {
            do {
                let jsonData = try Data(contentsOf: sharedFile)
                if let sharedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let filename = sharedData["filename"] as? String,
                   let pdfData = sharedData["data"] as? Data {
                    
                    // Process the shared PDF
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SharedPDFReceived"),
                        object: nil,
                        userInfo: ["filename": filename, "data": pdfData]
                    )
                    
                    // Clean up the shared file
                    try FileManager.default.removeItem(at: sharedFile)
                }
            } catch {
                print("Error processing shared PDF: \(error)")
            }
        }
    }
}