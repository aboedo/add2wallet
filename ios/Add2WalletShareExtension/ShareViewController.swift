import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers
import QuickLook

class ShareViewController: SLComposeServiceViewController, QLPreviewControllerDataSource {
    private var itemProvider: NSItemProvider?
    private var pdfTempURL: URL?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure the share extension UI
        title = "Add to Wallet"
        placeholder = "Converting PDF to Apple Wallet pass..."
        
        // Optional: keep a minimal UI; we provide actions via configuration items
        textView.isHidden = true
        loadSharedPDF()
    }
    
    override func isContentValid() -> Bool {
        // Content is always valid for our use case
        return true
    }
    
    override func didSelectPost() {
        // User tapped "Post"; treat as explicit action to hand off to the app
        sendToAdd2Wallet()
    }

    override func configurationItems() -> [Any]! {
        var items: [SLComposeSheetConfigurationItem] = []
        let previewItem = SLComposeSheetConfigurationItem()
        previewItem?.title = "Preview PDF"
        previewItem?.tapHandler = { [weak self] in
            self?.presentPreview()
        }
        if let previewItem { items.append(previewItem) }

        let sendItem = SLComposeSheetConfigurationItem()
        sendItem?.title = "Send to Add2Wallet"
        sendItem?.tapHandler = { [weak self] in
            self?.sendToAdd2Wallet()
        }
        if let sendItem { items.append(sendItem) }

        return items
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
    
    private func sendToAdd2Wallet() {
        guard let tempURL = pdfTempURL ?? (try? self.exportProviderToTemp()),
              let filename = tempURL?.lastPathComponent else {
            showError("No PDF available")
            return
        }

        do {
            let pdfData = try Data(contentsOf: tempURL!)

            // Save to shared container (App Group)
            guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.andresboedo.add2wallet") else {
                showError("Unable to access shared container")
                return
            }

            // Write the raw PDF
            let pdfOutURL = sharedContainer.appendingPathComponent("shared.pdf")
            try pdfData.write(to: pdfOutURL, options: .atomic)

            // Write metadata
            let metadata: [String: Any] = [
                "filename": filename,
                "timestamp": Date().timeIntervalSince1970
            ]
            let metadataURL = sharedContainer.appendingPathComponent("shared_pdf.json")
            let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: [])
            try jsonData.write(to: metadataURL, options: .atomic)

            // Update UI
            DispatchQueue.main.async { [weak self] in
                self?.placeholder = "Opening Add2Wallet..."
            }

            // Try to open the host app (user-initiated action)
            openMainApp()

        } catch {
            showError("Error preparing PDF: \(error.localizedDescription)")
        }
    }

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
        
        // Use openURL via responder chain (works better when triggered by user action)
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

    // MARK: - QLPreviewControllerDataSource
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { pdfTempURL == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return pdfTempURL! as NSURL
    }

    private func presentPreview() {
        guard let _ = pdfTempURL else {
            showError("PDF not ready to preview")
            return
        }
        let preview = QLPreviewController()
        preview.dataSource = self
        self.present(preview, animated: true)
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