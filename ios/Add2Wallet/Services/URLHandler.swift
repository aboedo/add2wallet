import Foundation
import UIKit

// MARK: - URL Handler

class URLHandler {
    
    // MARK: - Pending PDF Queue (survives race conditions)
    
    struct PendingPDF {
        let filename: String
        let data: Data
    }
    
    /// Pending PDF that hasn't been consumed by ContentViewModel yet
    static var pendingPDF: PendingPDF?
    
    /// Store a PDF for pickup by ContentViewModel, AND post the notification as fallback
    static func enqueuePDF(filename: String, data: Data) {
        print("🟢 URLHandler: Enqueuing PDF: \(filename) (\(data.count) bytes)")
        pendingPDF = PendingPDF(filename: filename, data: data)
        NotificationManager.postSharedPDFReceived(filename: filename, data: data)
    }
    
    /// Called by ContentViewModel on init to pick up any PDF that arrived before it was ready
    static func dequeuePendingPDF() -> PendingPDF? {
        guard let pdf = pendingPDF else { return nil }
        pendingPDF = nil
        print("🟢 URLHandler: Dequeued pending PDF: \(pdf.filename)")
        return pdf
    }
    
    // MARK: - URL Handling
    
    static func handleURL(_ url: URL) {
        print("🟢 URLHandler: handleURL called with: \(url)")
        print("🟢 URLHandler: URL scheme: \(url.scheme ?? "nil"), host: \(url.host ?? "nil")")
        print("🟢 URLHandler: URL path: \(url.path), isFileURL: \(url.isFileURL)")
        
        // Handle Universal Links for sharing (links.add2wallet.app/share/token)
        if url.host == "links.add2wallet.app" && url.pathComponents.count >= 3 && url.pathComponents[1] == "share" {
            let token = url.pathComponents[2]
            print("🟢 URLHandler: Handling Universal Link with token: \(token)")
            handleSharedPDFWithToken(token: token)
            return
        }
        
        // Handle custom URL scheme sharing (add2wallet://share/token)
        if url.scheme == "add2wallet" && url.host == "share" && url.pathComponents.count >= 2 {
            let token = url.pathComponents[1]
            print("🟢 URLHandler: Handling custom URL scheme with token: \(token)")
            handleSharedPDFWithToken(token: token)
            return
        }
        
        // Legacy support for old share-pdf scheme
        if url.scheme == "add2wallet" && url.host == "share-pdf" {
            print("🟢 URLHandler: Handling legacy share-pdf scheme")
            checkForSharedPDF()
            return
        }
        
        // Handle files opened via "Open in Add2Wallet"
        if url.isFileURL {
            print("🟢 URLHandler: Handling file URL: \(url)")
            handleFileURL(url)
        } else {
            print("🟡 URLHandler: URL not handled - not a file URL or recognized scheme")
        }
    }
    
    // MARK: - Private URL Handling Methods
    
    private static func handleFileURL(_ url: URL) {
        // Request access to security-scoped resource
        let hasAccess = url.startAccessingSecurityScopedResource()
        print("🟢 URLHandler: Security scoped resource access: \(hasAccess)")
        
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
                print("🟢 URLHandler: Stopped accessing security scoped resource")
            }
        }
        
        do {
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent
            print("🟢 URLHandler: Successfully loaded file data (\(data.count) bytes) for: \(filename)")
            
            enqueuePDF(filename: filename, data: data)
        } catch {
            print("🔴 URLHandler: Error loading file: \(error)")
        }
    }
    
    static func handleSharedPDFWithToken(token: String) {
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.andresboedo.add2wallet") else {
            print("🔴 URLHandler: Failed to access app group container")
            return
        }
        
        // Look for token-specific directory
        let tokenDir = sharedContainer.appendingPathComponent("shared").appendingPathComponent(token)
        let metadataFile = tokenDir.appendingPathComponent("metadata.json")
        let pdfFile = tokenDir.appendingPathComponent("document.pdf")
        
        if FileManager.default.fileExists(atPath: metadataFile.path),
           FileManager.default.fileExists(atPath: pdfFile.path) {
            do {
                // Read metadata
                let metadataData = try Data(contentsOf: metadataFile)
                let metadata = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any]
                let filename = metadata?["filename"] as? String ?? "shared_document.pdf"
                
                // Read PDF data
                let pdfData = try Data(contentsOf: pdfFile)
                
                print("🟢 URLHandler: Successfully processed shared PDF with token: \(token)")
                
                // Process the shared PDF
                enqueuePDF(filename: filename, data: pdfData)
                
                // Clean up the token directory
                try? FileManager.default.removeItem(at: tokenDir)
                print("🟢 URLHandler: Cleaned up token directory")
            } catch {
                print("🔴 URLHandler: Error processing shared PDF with token \(token): \(error)")
            }
        } else {
            print("🔴 URLHandler: Token directory or files not found for token: \(token)")
        }
    }
    
    static func checkForPendingShareToken() {
        let appGroupID = "group.com.andresboedo.add2wallet"
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let token = defaults.string(forKey: "pendingShareToken") else {
            return
        }
        
        // Clear immediately to avoid double-processing
        defaults.removeObject(forKey: "pendingShareToken")
        defaults.synchronize()
        
        print("🟢 URLHandler: Found pending share token: \(token)")
        handleSharedPDFWithToken(token: token)
    }
    
    static func checkForSharedPDF() {
        // Legacy support for old file-based sharing
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.andresboedo.add2wallet") else {
            print("🔴 URLHandler: Failed to access app group container for legacy sharing")
            return
        }
        
        let sharedFile = sharedContainer.appendingPathComponent("shared_pdf.json")
        let pdfFile = sharedContainer.appendingPathComponent("shared.pdf")

        if FileManager.default.fileExists(atPath: sharedFile.path),
           FileManager.default.fileExists(atPath: pdfFile.path) {
            do {
                let jsonData = try Data(contentsOf: sharedFile)
                if let sharedData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let filename = sharedData["filename"] as? String {
                    let pdfData = try Data(contentsOf: pdfFile)
                    
                    print("🟢 URLHandler: Successfully processed legacy shared PDF")
                    
                    // Process the shared PDF
                    enqueuePDF(filename: filename, data: pdfData)
                    
                    // Clean up the shared file
                    try? FileManager.default.removeItem(at: sharedFile)
                    try? FileManager.default.removeItem(at: pdfFile)
                    print("🟢 URLHandler: Cleaned up legacy shared files")
                }
            } catch {
                print("🔴 URLHandler: Error processing legacy shared PDF: \(error)")
            }
        } else {
            print("🟡 URLHandler: No legacy shared PDF files found")
        }
    }
}

// MARK: - URL Validation

extension URLHandler {
    
    static func isValidAdd2WalletURL(_ url: URL) -> Bool {
        // Check if URL is a valid Add2Wallet URL
        if url.host == "links.add2wallet.app" && url.pathComponents.count >= 3 && url.pathComponents[1] == "share" {
            return true
        }
        
        if url.scheme == "add2wallet" && (url.host == "share" || url.host == "share-pdf") {
            return true
        }
        
        return false
    }
    
    static func extractTokenFromURL(_ url: URL) -> String? {
        // Extract token from various URL formats
        if url.host == "links.add2wallet.app" && url.pathComponents.count >= 3 && url.pathComponents[1] == "share" {
            return url.pathComponents[2]
        }
        
        if url.scheme == "add2wallet" && url.host == "share" && url.pathComponents.count >= 2 {
            return url.pathComponents[1]
        }
        
        return nil
    }
}

// MARK: - Error Types

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