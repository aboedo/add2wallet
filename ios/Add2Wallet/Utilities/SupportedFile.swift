import Foundation
import UniformTypeIdentifiers

enum SupportedFile {
    static let heifType = UTType(filenameExtension: "heif") ?? UTType.image

    static let contentTypes: [UTType] = [
        .pdf,
        .jpeg,
        .png,
        .heic,
        heifType
    ]

    static func contentType(for filename: String) -> UTType? {
        let fileExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        guard let type = UTType(filenameExtension: fileExtension),
              isSupported(type) else {
            return nil
        }
        return type
    }

    static func contentType(forIdentifier identifier: String) -> UTType? {
        guard let type = UTType(identifier),
              isSupported(type) else {
            return nil
        }
        return type
    }

    static func isSupported(_ type: UTType) -> Bool {
        type.conforms(to: .pdf) ||
        type.conforms(to: .jpeg) ||
        type.conforms(to: .png) ||
        type.conforms(to: .heic) ||
        type.conforms(to: heifType)
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = contentType(for: url.lastPathComponent) else { return false }
        return type.conforms(to: .image)
    }

    static func mimeType(for filename: String) -> String {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "pdf":
            return "application/pdf"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "heic":
            return "image/heic"
        case "heif":
            return "image/heif"
        default:
            return contentType(for: filename)?.preferredMIMEType ?? "application/octet-stream"
        }
    }

    static func mimeType(forContentTypeIdentifier identifier: String?, filename: String) -> String {
        if let identifier,
           let mimeType = contentType(forIdentifier: identifier)?.preferredMIMEType {
            return mimeType
        }
        return mimeType(for: filename)
    }

    static func filename(_ suggestedName: String?, fallbackURL: URL?, type: UTType) -> String {
        let rawName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = (rawName?.isEmpty == false ? rawName : nil) ?? fallbackURL?.lastPathComponent ?? "shared_file"
        name = URL(fileURLWithPath: name).lastPathComponent

        if URL(fileURLWithPath: name).pathExtension.isEmpty,
           let fileExtension = type.preferredFilenameExtension {
            name += ".\(fileExtension)"
        }
        return name
    }
}
