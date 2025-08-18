import SwiftUI
import MessageUI

struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let pdfData: Data
    let fileName: String
    
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mailComposer = MFMailComposeViewController()
        mailComposer.mailComposeDelegate = context.coordinator
        mailComposer.setToRecipients(["andresboedo@gmail.com"])
        mailComposer.setSubject(subject)
        mailComposer.setMessageBody(body, isHTML: false)
        
        // Attach the PDF file
        mailComposer.addAttachmentData(pdfData, mimeType: "application/pdf", fileName: fileName)
        
        return mailComposer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposeView
        
        init(_ parent: MailComposeView) {
            self.parent = parent
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            // Handle the result if needed
            switch result {
            case .sent:
                print("Email sent successfully")
            case .cancelled:
                print("Email cancelled")
            case .saved:
                print("Email saved as draft")
            case .failed:
                print("Email failed to send: \(error?.localizedDescription ?? "Unknown error")")
            @unknown default:
                print("Unknown email result")
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}