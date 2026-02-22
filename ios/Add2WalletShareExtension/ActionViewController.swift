import UIKit

/// Minimal share extension — guides user to "Copy to Add2Wallet" which works natively.
class ActionViewController: UIViewController {
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let alert = UIAlertController(
            title: "Tip 💡",
            message: "For the best experience, use \"Copy to Add2Wallet\" instead.\n\nLong-press the PDF → Share → look for Add2Wallet in the apps row.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Got it", style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        })
        present(alert, animated: true)
    }
}
