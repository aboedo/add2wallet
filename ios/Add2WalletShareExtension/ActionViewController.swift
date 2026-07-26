import UIKit
import UniformTypeIdentifiers

final class ActionViewController: UIViewController {
    private let appGroupID = "group.com.andresboedo.add2wallet"
    private var hasStarted = false

    private static let heifType = UTType(filenameExtension: "heif") ?? .image
    private static let supportedTypes: [UTType] = [.pdf, .jpeg, .png, .heic, heifType]

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else { return }
        hasStarted = true
        importFirstSupportedAttachment()
    }

    private func importFirstSupportedAttachment() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finishWithError("No file was shared.")
            return
        }

        for attachment in items.compactMap(\.attachments).flatMap({ $0 }) {
            for type in Self.supportedTypes where attachment.hasItemConformingToTypeIdentifier(type.identifier) {
                load(attachment, as: type)
                return
            }
        }

        finishWithError("Choose a PDF, JPEG, PNG, HEIC, or HEIF file.")
    }

    private func load(_ provider: NSItemProvider, as type: UTType) {
        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] url, error in
            guard let self else { return }

            do {
                if let error { throw error }
                guard let url else { throw ShareError.missingFile }

                let data = try Data(contentsOf: url)
                let filename = Self.originalFilename(
                    suggestedName: provider.suggestedName,
                    fallbackURL: url,
                    type: type
                )
                let token = try persist(data: data, filename: filename, type: type)
                openHostApp(token: token)
            } catch {
                finishWithError("Couldn't share this file: \(error.localizedDescription)")
            }
        }
    }

    private func persist(data: Data, filename: String, type: UTType) throws -> String {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            throw ShareError.missingAppGroup
        }

        let token = UUID().uuidString
        let directory = container
            .appendingPathComponent("shared", isDirectory: true)
            .appendingPathComponent(token, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let safeFilename = URL(fileURLWithPath: filename).lastPathComponent
        let fileURL = directory.appendingPathComponent(safeFilename)
        try data.write(to: fileURL, options: [.atomic])

        let metadata: [String: String] = [
            "filename": safeFilename,
            "storedFilename": safeFilename,
            "contentType": type.identifier
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        try metadataData.write(to: directory.appendingPathComponent("metadata.json"), options: [.atomic])

        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            throw ShareError.missingAppGroup
        }
        defaults.set(token, forKey: "pendingShareToken")
        defaults.synchronize()
        return token
    }

    private func openHostApp(token: String) {
        guard let url = URL(string: "add2wallet://share/\(token)") else {
            finishWithError("Open Add2Wallet to continue.")
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.open(url) { _ in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }

    private func finishWithError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let alert = UIAlertController(title: "Add2Wallet", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            })
            present(alert, animated: true)
        }
    }

    private static func originalFilename(suggestedName: String?, fallbackURL: URL, type: UTType) -> String {
        let suggested = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = suggested?.isEmpty == false ? suggested! : fallbackURL.lastPathComponent
        var filename = URL(fileURLWithPath: candidate).lastPathComponent

        if URL(fileURLWithPath: filename).pathExtension.isEmpty,
           let fileExtension = type.preferredFilenameExtension {
            filename += ".\(fileExtension)"
        }
        return filename
    }
}

private enum ShareError: LocalizedError {
    case missingFile
    case missingAppGroup

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "The shared file is no longer available."
        case .missingAppGroup:
            return "Add2Wallet's shared storage is unavailable."
        }
    }
}
