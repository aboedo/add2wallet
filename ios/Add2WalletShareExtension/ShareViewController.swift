import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        handleSharedContent()
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor.systemBackground
        
        let titleLabel = UILabel()
        titleLabel.text = "Add to Wallet"
        titleLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let messageLabel = UILabel()
        messageLabel.text = "Converting PDF to Apple Wallet pass..."
        messageLabel.font = UIFont.systemFont(ofSize: 16)
        messageLabel.textAlignment = .center
        messageLabel.textColor = UIColor.secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.startAnimating()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        let stackView = UIStackView(arrangedSubviews: [titleLabel, messageLabel, activityIndicator])
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
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
            
            // Pass data to main app via shared container or URL scheme
            let sharedData: [String: Any] = [
                "filename": filename,
                "data": pdfData,
                "timestamp": Date().timeIntervalSince1970
            ]
            
            // Save to shared container (App Group)
            if let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.andresboedo.add2wallet") {
                let sharedFile = sharedContainer.appendingPathComponent("shared_pdf.json")
                
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: sharedData)
                    try jsonData.write(to: sharedFile)
                    
                    // Open main app
                    openMainApp()
                } catch {
                    showError("Error saving PDF: \(error.localizedDescription)")
                }
            } else {
                showError("Unable to access shared container")
            }
            
        } catch {
            showError("Error reading PDF: \(error.localizedDescription)")
        }
    }
    
    private func openMainApp() {
        // Try to open the main app
        if let url = URL(string: "add2wallet://share-pdf") {
            var responder = self as UIResponder?
            let selectorOpenURL = sel_registerName("openURL:")
            
            while responder != nil {
                if responder!.responds(to: selectorOpenURL) {
                    responder!.perform(selectorOpenURL, with: url)
                    break
                }
                responder = responder!.next
            }
        }
        
        // Close the extension
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            })
            self?.present(alert, animated: true)
        }
    }
}