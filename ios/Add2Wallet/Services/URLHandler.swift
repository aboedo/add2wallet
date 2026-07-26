import Foundation

// MARK: - URL Handler

class URLHandler {
    struct PendingFile {
        let filename: String
        let data: Data
        let contentTypeIdentifier: String?
    }

    private static var pendingFile: PendingFile?

    static func enqueueFile(filename: String, data: Data, contentTypeIdentifier: String? = nil) {
        let safeFilename = URL(fileURLWithPath: filename).lastPathComponent
        let contentType = contentTypeIdentifier.flatMap(SupportedFile.contentType(forIdentifier:))
            ?? SupportedFile.contentType(for: safeFilename)
        guard let contentType else {
            print("🔴 URLHandler: Unsupported file type: \(safeFilename)")
            return
        }

        print("🟢 URLHandler: Enqueuing file: \(safeFilename) (\(data.count) bytes)")
        pendingFile = PendingFile(filename: safeFilename, data: data, contentTypeIdentifier: contentType.identifier)
        NotificationManager.postSharedFileReceived(
            filename: safeFilename,
            data: data,
            contentTypeIdentifier: contentType.identifier
        )
        NotificationCenter.default.post(name: NSNotification.Name("SwitchToGeneratePassTab"), object: nil)
    }

    static func dequeuePendingFile() -> PendingFile? {
        guard let file = pendingFile else { return nil }
        pendingFile = nil
        return file
    }

    static func handleURL(_ url: URL) {
        if url.host == "links.add2wallet.app",
           url.pathComponents.count >= 3,
           url.pathComponents[1] == "share" {
            handleSharedFile(withToken: url.pathComponents[2])
            return
        }

        if url.scheme == "add2wallet",
           url.host == "share",
           url.pathComponents.count >= 2 {
            handleSharedFile(withToken: url.pathComponents[1])
            return
        }

        if url.scheme == "add2wallet" && url.host == "share-pdf" {
            checkForSharedFile()
            return
        }

        if url.isFileURL {
            handleFileURL(url)
        }
    }

    private static func handleFileURL(_ url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            enqueueFile(filename: url.lastPathComponent, data: try Data(contentsOf: url))
        } catch {
            print("🔴 URLHandler: Error loading file: \(error)")
        }
    }

    static func handleSharedFile(withToken token: String) {
        guard let sharedContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.andresboedo.add2wallet"
        ) else {
            print("🔴 URLHandler: Failed to access app group container")
            return
        }

        handleSharedFile(withToken: token, sharedContainer: sharedContainer)
    }

    static func handleSharedFile(withToken token: String, sharedContainer: URL) {
        let tokenDirectory = sharedContainer
            .appendingPathComponent("shared", isDirectory: true)
            .appendingPathComponent(token, isDirectory: true)
        let metadataURL = tokenDirectory.appendingPathComponent("metadata.json")

        do {
            let metadataData = try Data(contentsOf: metadataURL)
            let metadata = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any]
            let originalFilename = metadata?["filename"] as? String
            let storedFilename = metadata?["storedFilename"] as? String
            let contentTypeIdentifier = metadata?["contentType"] as? String
            let fileURL = try sharedFileURL(
                in: tokenDirectory,
                storedFilename: storedFilename,
                originalFilename: originalFilename
            )
            let filename = originalFilename ?? fileURL.lastPathComponent
            let data = try Data(contentsOf: fileURL)

            enqueueFile(filename: filename, data: data, contentTypeIdentifier: contentTypeIdentifier)
            try? FileManager.default.removeItem(at: tokenDirectory)
        } catch {
            print("🔴 URLHandler: Error processing shared file with token \(token): \(error)")
        }
    }

    private static func sharedFileURL(
        in directory: URL,
        storedFilename: String?,
        originalFilename: String?
    ) throws -> URL {
        let candidates = [storedFilename, originalFilename]
            .compactMap { $0 }
            .map { directory.appendingPathComponent(URL(fileURLWithPath: $0).lastPathComponent) }

        if let candidate = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return candidate
        }

        // Backward compatibility with the former PDF-only handoff.
        let legacyURL = directory.appendingPathComponent("document.pdf")
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        if let file = files.first(where: { $0.lastPathComponent != "metadata.json" }) {
            return file
        }

        throw URLHandlerError.fileNotFound(originalFilename ?? "shared file")
    }

    static func checkForPendingShareToken() {
        let appGroupID = "group.com.andresboedo.add2wallet"
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let token = defaults.string(forKey: "pendingShareToken") else {
            return
        }

        defaults.removeObject(forKey: "pendingShareToken")
        defaults.synchronize()
        handleSharedFile(withToken: token)
    }

    static func checkForSharedFile() {
        guard let sharedContainer = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.andresboedo.add2wallet"
        ) else { return }

        checkForSharedFile(in: sharedContainer)
    }

    static func checkForSharedFile(in sharedContainer: URL) {
        let metadataURL = sharedContainer.appendingPathComponent("shared_pdf.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return }

        do {
            let metadataData = try Data(contentsOf: metadataURL)
            let metadata = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any]
            guard let filename = metadata?["filename"] as? String else {
                throw URLHandlerError.dataCorrupted
            }

            let storedFilename = metadata?["storedFilename"] as? String
            let candidates = [storedFilename, filename, "shared.pdf"]
                .compactMap { $0 }
                .map { sharedContainer.appendingPathComponent(URL(fileURLWithPath: $0).lastPathComponent) }
            guard let fileURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                throw URLHandlerError.fileNotFound(filename)
            }

            enqueueFile(
                filename: filename,
                data: try Data(contentsOf: fileURL),
                contentTypeIdentifier: metadata?["contentType"] as? String
            )
            try? FileManager.default.removeItem(at: metadataURL)
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            print("🔴 URLHandler: Error processing legacy shared file: \(error)")
        }
    }

    // Compatibility with the previous API name.
    static func checkForSharedPDF() {
        checkForSharedFile()
    }
}

extension URLHandler {
    static func isValidAdd2WalletURL(_ url: URL) -> Bool {
        if url.host == "links.add2wallet.app",
           url.pathComponents.count >= 3,
           url.pathComponents[1] == "share" {
            return true
        }
        return url.scheme == "add2wallet" && (url.host == "share" || url.host == "share-pdf")
    }

    static func extractTokenFromURL(_ url: URL) -> String? {
        if url.host == "links.add2wallet.app",
           url.pathComponents.count >= 3,
           url.pathComponents[1] == "share" {
            return url.pathComponents[2]
        }
        if url.scheme == "add2wallet",
           url.host == "share",
           url.pathComponents.count >= 2 {
            return url.pathComponents[1]
        }
        return nil
    }
}

enum URLHandlerError: Error, LocalizedError {
    case invalidURL
    case securityScopedResourceAccessFailed
    case appGroupContainerNotFound
    case fileNotFound(String)
    case dataCorrupted

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL format"
        case .securityScopedResourceAccessFailed:
            return "Failed to access security scoped resource"
        case .appGroupContainerNotFound:
            return "App group container not found"
        case .fileNotFound(let filename):
            return "File not found: \(filename)"
        case .dataCorrupted:
            return "Data is corrupted or invalid"
        }
    }
}
