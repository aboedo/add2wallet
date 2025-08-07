import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

class ActionViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Minimal UI; proceed immediately with user-visible button
        presentOpenButton()
    }

    private func presentOpenButton() {
        let alert = UIAlertController(title: "Open Add2Wallet", message: "We will open the app to continue.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        })
        alert.addAction(UIAlertAction(title: "Open", style: .default) { _ in
            self.openHostApp()
        })
        present(alert, animated: true)
    }

    private func openHostApp() {
        guard let url = URL(string: "add2wallet://share-pdf") else {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }
        self.extensionContext?.open(url, completionHandler: { _ in
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        })
    }
}
