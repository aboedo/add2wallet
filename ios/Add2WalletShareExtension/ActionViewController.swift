import UIKit
import UniformTypeIdentifiers

class ActionViewController: UIViewController {
    
    private let appGroupID = "group.com.andresboedo.add2wallet"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
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
        guard error == nil else { done(); return }
        
        var pdfData: Data?
        var filename = "shared.pdf"
        
        if let url = data as? URL {
            pdfData = try? Data(contentsOf: url)
            filename = url.lastPathComponent
        } else if let d = data as? Data {
            pdfData = d
        }
        
        guard let validData = pdfData else { done(); return }
        
        // Save to App Group shared container
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            done()
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
            
            // Write pending token to shared UserDefaults so the app picks it up
            let defaults = UserDefaults(suiteName: appGroupID)
            defaults?.set(token, forKey: "pendingShareToken")
            defaults?.synchronize()
            
            // Open the main app via URL scheme
            if let url = URL(string: "add2wallet://share/\(token)") {
                // extensionContext?.open() works for action extensions on iOS 16+
                extensionContext?.open(url, completionHandler: { [weak self] success in
                    if !success {
                        // URL scheme failed — that's OK, the app will pick up the
                        // pending token from UserDefaults when it comes to foreground
                        print("URL scheme open failed, relying on foreground detection")
                    }
                    self?.done()
                })
                return
            }
        } catch {
            print("Share extension error: \(error)")
        }
        
        done()
    }
    
    private func done() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
