import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

class ActionViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Extract PDF data and present option to open app
        extractPDFAndPresentOption()
    }

    private func extractPDFAndPresentOption() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            showError("No items to share")
            return
        }
        
        // Find PDF attachment
        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    extractPDF(from: provider)
                    return
                }
            }
        }
        
        showError("No PDF found to share")
    }
    
    private func extractPDF(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { [weak self] (data, error) in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showError("Error loading PDF: \(error.localizedDescription)")
                    return
                }
                
                var pdfData: Data?
                var filename: String = "shared_document.pdf"
                
                if let url = data as? URL {
                    // PDF provided as URL
                    do {
                        pdfData = try Data(contentsOf: url)
                        filename = url.lastPathComponent
                    } catch {
                        self?.showError("Error reading PDF: \(error.localizedDescription)")
                        return
                    }
                } else if let dataObject = data as? Data {
                    // PDF provided as raw data
                    pdfData = dataObject
                }
                
                guard let validPDFData = pdfData else {
                    self?.showError("Invalid PDF data")
                    return
                }
                
                // Save PDF to App Group container and generate token
                if let token = self?.savePDFToAppGroup(data: validPDFData, filename: filename) {
                    self?.presentOpenAppOption(with: token)
                } else {
                    self?.showError("Error saving PDF")
                }
            }
        }
    }
    
    private func savePDFToAppGroup(data: Data, filename: String) -> String? {
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.andresboedo.add2wallet") else {
            return nil
        }
        
        // Generate unique token for this sharing session
        let token = UUID().uuidString
        
        // Create token-specific directory
        let tokenDir = sharedContainer.appendingPathComponent("shared").appendingPathComponent(token)
        
        do {
            try FileManager.default.createDirectory(at: tokenDir, withIntermediateDirectories: true)
            
            // Save PDF data
            let pdfFile = tokenDir.appendingPathComponent("document.pdf")
            try data.write(to: pdfFile)
            
            // Save metadata
            let metadata = [
                "filename": filename,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "size": data.count
            ] as [String: Any]
            
            let metadataData = try JSONSerialization.data(withJSONObject: metadata)
            let metadataFile = tokenDir.appendingPathComponent("metadata.json")
            try metadataData.write(to: metadataFile)
            
            return token
        } catch {
            return nil
        }
    }

    private func presentOpenAppOption(with token: String) {
        let alert = UIAlertController(title: "Add to Wallet", message: "Open Add2Wallet to convert this PDF to an Apple Wallet pass.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        })
        alert.addAction(UIAlertAction(title: "Open App", style: .default) { _ in
            self.openHostApp(with: token)
        })
        present(alert, animated: true)
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        })
        present(alert, animated: true)
    }

    private func openHostApp(with token: String) {
        // First try Universal Link
        let universalLinkURL = URL(string: "https://links.add2wallet.app/share/\(token)")
        
        // Fallback to custom URL scheme
        let customSchemeURL = URL(string: "add2wallet://share/\(token)")
        
        // Try Universal Link first
        if let universalURL = universalLinkURL {
            var responder: UIResponder? = self as UIResponder
            let selector = NSSelectorFromString("openURL:")
            
            while responder != nil {
                if responder!.responds(to: selector) {
                    _ = responder!.perform(selector, with: universalURL)
                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                    return
                }
                responder = responder?.next
            }
        }
        
        // Fallback to custom scheme
        if let customURL = customSchemeURL {
            var responder: UIResponder? = self as UIResponder
            let selector = NSSelectorFromString("openURL:")
            
            while responder != nil {
                if responder!.responds(to: selector) {
                    _ = responder!.perform(selector, with: customURL)
                    break
                }
                responder = responder?.next
            }
            
            // Also try extension context open as fallback
            self.extensionContext?.open(customURL, completionHandler: { _ in })
        }
        
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
