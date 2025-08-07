import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {
    private var itemProvider: NSItemProvider?
    private var pdfTempURL: URL?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure the share extension UI
        title = "Add to Wallet"
        placeholder = "Converting PDF to Apple Wallet pass..."
        
        // Minimal UI; user taps Post to proceed
        textView.isHidden = true
        // For testing: don't load or process the shared item. We'll only open the app.
    }
    
    override func isContentValid() -> Bool {
        // Content is always valid for our use case
        return true
    }
    
    override func didSelectPost() {
        // For testing: do nothing but open the host app
        openMainApp()
    }

    private func loadSharedPDF() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = extensionItem.attachments?.first else {
            showError("No content to share")
            return
        }
        self.itemProvider = provider

        guard provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) else {
            showError("Only PDF files are supported")
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { [weak self] (item, error) in
            if let error = error {
                self?.showError("Error loading PDF: \(error.localizedDescription)")
                return
            }

            guard let url = item as? URL else {
                self?.showError("Invalid PDF file")
                return
            }

            // Copy to a temp URL inside the extension for preview
            let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("shared-preview.pdf")
            do {
                if FileManager.default.fileExists(atPath: tmpURL.path) {
                    try? FileManager.default.removeItem(at: tmpURL)
                }
                try FileManager.default.copyItem(at: url, to: tmpURL)
                self?.pdfTempURL = tmpURL
            } catch {
                self?.showError("Error preparing preview: \(error.localizedDescription)")
            }
        }
    }
    
    // For testing, skip writing any files and just open the app

    private func exportProviderToTemp() throws -> URL? {
        guard let provider = self.itemProvider else { return nil }
        var outURL: URL?
        let semaphore = DispatchSemaphore(value: 0)
        provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { (item, _) in
            if let url = item as? URL {
                let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("shared-preview.pdf")
                try? FileManager.default.copyItem(at: url, to: tmpURL)
                outURL = tmpURL
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return outURL
    }
    
    private func openMainApp() {
        // Update UI to show we're opening the app
        DispatchQueue.main.async { [weak self] in
            self?.placeholder = "Opening Add2Wallet..."
        }
        
        // Use extensionContext open to foreground host app
        guard let url = URL(string: "add2wallet://share-pdf") else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
            return
        }

        extensionContext?.open(url, completionHandler: { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        })
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