import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure the share extension UI
        title = "Add to Wallet"
        placeholder = "Converting PDF to Apple Wallet pass..."
        
        // Hide the text view since we're just processing
        textView.isHidden = true
        
        // Process the shared content immediately
        handleSharedContent()
    }
    
    override func isContentValid() -> Bool {
        // Content is always valid for our use case
        return true
    }
    
    override func didSelectPost() {
        // This will be called when user taps "Post" but we handle everything automatically
        extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    private func handleSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            showError("No content to share")
            return
        }
        
        // Check if the item is a PDF
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            itemProvider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { [weak self] (item, error) in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.showError("Error loading PDF: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let url = item as? URL else {
                        self?.showError("Invalid PDF file")
                        return
                    }
                    
                    self?.processPDF(at: url)
                }
            }
        } else {
            showError("Only PDF files are supported")
        }
    }
    
    private func processPDF(at url: URL) {
        do {
            let pdfData = try Data(contentsOf: url)
            let filename = url.lastPathComponent
            
            // Save to shared container (App Group)
            guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.andresboedo.add2wallet") else {
                showError("Unable to access shared container")
                return
            }

            // Write the raw PDF to a known file name
            let pdfOutURL = sharedContainer.appendingPathComponent("shared.pdf")
            do {
                try pdfData.write(to: pdfOutURL, options: .atomic)
            } catch {
                showError("Error saving PDF: \(error.localizedDescription)")
                return
            }

            // Write lightweight metadata JSON (no raw Data types)
            let metadata: [String: Any] = [
                "filename": filename,
                "timestamp": Date().timeIntervalSince1970
            ]
            let metadataURL = sharedContainer.appendingPathComponent("shared_pdf.json")
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: [])
                try jsonData.write(to: metadataURL, options: .atomic)
            } catch {
                showError("Error saving metadata: \(error.localizedDescription)")
                return
            }

            // Update UI to show success
            DispatchQueue.main.async { [weak self] in
                self?.placeholder = "PDF saved! Opening Add2Wallet..."
            }

            // Open main app
            openMainApp()
            
        } catch {
            showError("Error reading PDF: \(error.localizedDescription)")
        }
    }
    
    private func openMainApp() {
        // Update UI to show we're opening the app
        DispatchQueue.main.async { [weak self] in
            self?.placeholder = "Opening Add2Wallet..."
        }
        
        // Preferred: use openURL via responder chain from extension to host app
        guard let url = URL(string: "add2wallet://share-pdf") else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
            return
        }

        var responder: UIResponder? = self as UIResponder
        let selector = NSSelectorFromString("openURL:")
        while responder != nil {
            if responder!.responds(to: selector) {
                _ = responder!.perform(selector, with: url)
                break
            }
            responder = responder?.next
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            // Update the UI to show error state
            self?.placeholder = "Error: \(message)"
            
            // Close the extension after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }
}