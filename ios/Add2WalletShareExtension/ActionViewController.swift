import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

class ActionViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        print("🟢 Share Extension: ViewDidLoad called")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("🟢 Share Extension: ViewDidAppear called")
        // Extract PDF data and immediately open app
        extractPDFAndOpenApp()
    }

    private func extractPDFAndOpenApp() {
        print("🟢 Share Extension: extractPDFAndOpenApp called")
        
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            print("🔴 Share Extension: No extension items found")
            completeWithError("No items to share")
            return
        }
        
        print("🟢 Share Extension: Found \(extensionItems.count) extension items")
        
        // Find PDF attachment
        for (itemIndex, item) in extensionItems.enumerated() {
            print("🟢 Share Extension: Processing item \(itemIndex)")
            guard let attachments = item.attachments else { 
                print("🟡 Share Extension: No attachments in item \(itemIndex)")
                continue 
            }
            
            print("🟢 Share Extension: Found \(attachments.count) attachments in item \(itemIndex)")
            
            for (attachmentIndex, provider) in attachments.enumerated() {
                print("🟢 Share Extension: Processing attachment \(attachmentIndex)")
                let typeIdentifiers = provider.registeredTypeIdentifiers
                print("🟢 Share Extension: Type identifiers: \(typeIdentifiers)")
                
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    print("🟢 Share Extension: Found PDF attachment!")
                    extractPDFAndOpenApp(from: provider)
                    return
                }
            }
        }
        
        print("🔴 Share Extension: No PDF found in any attachments")
        completeWithError("No PDF found to share")
    }
    
    private func extractPDFAndOpenApp(from provider: NSItemProvider) {
        print("🟢 Share Extension: Starting PDF extraction")
        provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { [weak self] (data, error) in
            DispatchQueue.main.async {
                print("🟢 Share Extension: PDF load completed")
                if let error = error {
                    print("🔴 Share Extension: Error loading PDF: \(error)")
                    self?.completeWithError("Error loading PDF: \(error.localizedDescription)")
                    return
                }
                
                var pdfData: Data?
                var filename: String = "shared_document.pdf"
                
                if let url = data as? URL {
                    print("🟢 Share Extension: PDF provided as URL: \(url)")
                    // PDF provided as URL
                    do {
                        pdfData = try Data(contentsOf: url)
                        filename = url.lastPathComponent
                        print("🟢 Share Extension: Successfully read PDF data (\(pdfData?.count ?? 0) bytes)")
                    } catch {
                        print("🔴 Share Extension: Error reading PDF from URL: \(error)")
                        self?.completeWithError("Error reading PDF: \(error.localizedDescription)")
                        return
                    }
                } else if let dataObject = data as? Data {
                    print("🟢 Share Extension: PDF provided as raw data (\(dataObject.count) bytes)")
                    // PDF provided as raw data
                    pdfData = dataObject
                } else {
                    print("🔴 Share Extension: Unknown data type: \(type(of: data))")
                }
                
                guard let validPDFData = pdfData else {
                    print("🔴 Share Extension: No valid PDF data found")
                    self?.completeWithError("Invalid PDF data")
                    return
                }
                
                print("🟢 Share Extension: Saving PDF to App Group container")
                // Save PDF to App Group container and generate token
                if let token = self?.savePDFToAppGroup(data: validPDFData, filename: filename) {
                    print("🟢 Share Extension: Successfully saved PDF with token: \(token)")
                    self?.openHostApp(with: token)
                } else {
                    print("🔴 Share Extension: Failed to save PDF to App Group")
                    self?.completeWithError("Error saving PDF")
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

    private func completeWithError(_ message: String) {
        // In a production app, you might want to log this error
        print("Share Extension Error: \(message)")
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
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
