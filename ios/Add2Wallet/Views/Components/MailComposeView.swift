import SwiftUI
import MessageUI

struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let attachmentData: Data
    let attachmentMIMEType: String
    let fileName: String

    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mailComposer = MFMailComposeViewController()
        mailComposer.mailComposeDelegate = context.coordinator
        mailComposer.setToRecipients(["andresboedo@gmail.com"])
        mailComposer.setSubject(subject)
        mailComposer.setMessageBody(body, isHTML: false)
        mailComposer.addAttachmentData(
            attachmentData,
            mimeType: attachmentMIMEType,
            fileName: fileName
        )
        return mailComposer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposeView

        init(_ parent: MailComposeView) {
            self.parent = parent
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            if result == .failed {
                print("Email failed to send: \(error?.localizedDescription ?? "Unknown error")")
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
