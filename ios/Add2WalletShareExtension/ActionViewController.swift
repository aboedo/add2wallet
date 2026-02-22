import UIKit
import UniformTypeIdentifiers

class ActionViewController: UIViewController {
    
    private let appGroupID = "group.com.andresboedo.add2wallet"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        extractPDFAndHandoff()
    }
    
    private func extractPDFAndHandoff() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            done()
            return
        }
        
        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { [weak self] data, error in
                        DispatchQueue.main.async {
                            self?.handleLoadedItem(data: data, error: error)
                        }
                    }
                    return
                }
            }
        }
        done()
    }
    
    private func handleLoadedItem(data: Any?, error: Error?) {
        guard error == nil else {
            showError("Could not read the PDF.")
            return
        }
        
        var pdfData: Data?
        var filename = "shared.pdf"
        
        if let url = data as? URL {
            pdfData = try? Data(contentsOf: url)
            filename = url.lastPathComponent
        } else if let d = data as? Data {
            pdfData = d
        }
        
        guard let validData = pdfData else {
            showError("Invalid PDF data.")
            return
        }
        
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            showError("Storage error.")
            return
        }
        
        let token = UUID().uuidString
        let tokenDir = container.appendingPathComponent("shared").appendingPathComponent(token)
        
        do {
            try FileManager.default.createDirectory(at: tokenDir, withIntermediateDirectories: true)
            try validData.write(to: tokenDir.appendingPathComponent("document.pdf"))
            
            let metadata: [String: Any] = [
                "filename": filename,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "size": validData.count
            ]
            let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)
            try metadataJSON.write(to: tokenDir.appendingPathComponent("metadata.json"))
            
            // Write pending token so the app picks it up on foreground
            let defaults = UserDefaults(suiteName: appGroupID)
            defaults?.set(token, forKey: "pendingShareToken")
            defaults?.synchronize()
            
            // Try to open the app directly
            if let url = URL(string: "add2wallet://share/\(token)") {
                extensionContext?.open(url) { [weak self] success in
                    DispatchQueue.main.async {
                        if success {
                            self?.done()
                        } else {
                            // Can't open app — tell user to do it manually
                            self?.showSuccess(filename: filename)
                        }
                    }
                }
            } else {
                showSuccess(filename: filename)
            }
        } catch {
            showError("Could not save PDF.")
        }
    }
    
    private func showSuccess(filename: String) {
        let alert = UIAlertController(
            title: "PDF Ready! 🎫",
            message: "\(filename) has been imported. Open Add2Wallet to create your pass.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.done()
        })
        present(alert, animated: true)
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.done()
        })
        present(alert, animated: true)
    }
    
    private func done() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
