import Foundation
import UIKit

// MARK: - Notification Manager

class NotificationManager {
    
    // MARK: - Notification Names
    
    enum NotificationName: String, CaseIterable {
        case sharedPDFReceived = "SharedPDFReceived"
        case passReadyToAdd = "PassReadyToAdd"
        case passGenerated = "PassGenerated"
        case resetPassUIState = "ResetPassUIState"
        case showSupportEmail = "ShowSupportEmail"
        
        var notificationName: NSNotification.Name {
            return NSNotification.Name(self.rawValue)
        }
    }
    
    // MARK: - Posting Notifications
    
    static func postSharedPDFReceived(filename: String, data: Data) {
        NotificationCenter.default.post(
            name: NotificationName.sharedPDFReceived.notificationName,
            object: nil,
            userInfo: [
                "filename": filename,
                "data": data
            ]
        )
        print("📢 NotificationManager: Posted SharedPDFReceived - \(filename) (\(data.count) bytes)")
    }
    
    static func postPassReadyToAdd(passViewController: UIViewController, tempURL: URL? = nil) {
        var userInfo: [AnyHashable: Any] = ["passViewController": passViewController]
        if let tempURL = tempURL {
            userInfo["tempURL"] = tempURL
        }
        
        NotificationCenter.default.post(
            name: NotificationName.passReadyToAdd.notificationName,
            object: nil,
            userInfo: userInfo
        )
        print("📢 NotificationManager: Posted PassReadyToAdd")
    }
    
    static func postPassGenerated(message: String) {
        NotificationCenter.default.post(
            name: NotificationName.passGenerated.notificationName,
            object: nil,
            userInfo: ["message": message]
        )
        print("📢 NotificationManager: Posted PassGenerated - \(message)")
    }
    
    static func postResetPassUIState() {
        NotificationCenter.default.post(
            name: NotificationName.resetPassUIState.notificationName,
            object: nil
        )
        print("📢 NotificationManager: Posted ResetPassUIState")
    }
    
    static func postShowSupportEmail(subject: String, body: String, pdfData: Data, fileName: String) {
        let userInfo: [AnyHashable: Any] = [
            "subject": subject,
            "body": body,
            "pdfData": pdfData,
            "fileName": fileName
        ]
        
        NotificationCenter.default.post(
            name: NotificationName.showSupportEmail.notificationName,
            object: nil,
            userInfo: userInfo
        )
        print("📢 NotificationManager: Posted ShowSupportEmail - \(subject)")
    }
    
    // MARK: - Observer Management
    
    static func addObserver(
        for notificationName: NotificationName,
        observer: Any,
        selector: Selector,
        object: Any? = nil
    ) {
        NotificationCenter.default.addObserver(
            observer,
            selector: selector,
            name: notificationName.notificationName,
            object: object
        )
        print("📢 NotificationManager: Added observer for \(notificationName.rawValue)")
    }
    
    static func addObserver(
        for notificationName: NotificationName,
        queue: OperationQueue? = .main,
        using block: @escaping (Notification) -> Void
    ) -> NSObjectProtocol {
        let observer = NotificationCenter.default.addObserver(
            forName: notificationName.notificationName,
            object: nil,
            queue: queue,
            using: block
        )
        print("📢 NotificationManager: Added block observer for \(notificationName.rawValue)")
        return observer
    }
    
    static func removeObserver(_ observer: Any) {
        NotificationCenter.default.removeObserver(observer)
        print("📢 NotificationManager: Removed observer")
    }
    
    static func removeObserver(_ observer: Any, for notificationName: NotificationName) {
        NotificationCenter.default.removeObserver(
            observer,
            name: notificationName.notificationName,
            object: nil
        )
        print("📢 NotificationManager: Removed observer for \(notificationName.rawValue)")
    }
    
    // MARK: - Convenience Methods for Common Patterns
    
    static func observeSharedPDFReceived(using block: @escaping (String, Data) -> Void) -> NSObjectProtocol {
        return addObserver(for: .sharedPDFReceived) { notification in
            guard let userInfo = notification.userInfo,
                  let filename = userInfo["filename"] as? String,
                  let data = userInfo["data"] as? Data else {
                print("🔴 NotificationManager: Invalid SharedPDFReceived notification userInfo")
                return
            }
            block(filename, data)
        }
    }
    
    static func observePassReadyToAdd(using block: @escaping (UIViewController, URL?) -> Void) -> NSObjectProtocol {
        return addObserver(for: .passReadyToAdd) { notification in
            guard let userInfo = notification.userInfo,
                  let passViewController = userInfo["passViewController"] as? UIViewController else {
                print("🔴 NotificationManager: Invalid PassReadyToAdd notification userInfo")
                return
            }
            let tempURL = userInfo["tempURL"] as? URL
            block(passViewController, tempURL)
        }
    }
    
    static func observePassGenerated(using block: @escaping (String) -> Void) -> NSObjectProtocol {
        return addObserver(for: .passGenerated) { notification in
            guard let userInfo = notification.userInfo,
                  let message = userInfo["message"] as? String else {
                print("🔴 NotificationManager: Invalid PassGenerated notification userInfo")
                return
            }
            block(message)
        }
    }
    
    static func observeResetPassUIState(using block: @escaping () -> Void) -> NSObjectProtocol {
        return addObserver(for: .resetPassUIState) { _ in
            block()
        }
    }
    
    static func observeShowSupportEmail(using block: @escaping (String, String, Data, String) -> Void) -> NSObjectProtocol {
        return addObserver(for: .showSupportEmail) { notification in
            guard let userInfo = notification.userInfo,
                  let subject = userInfo["subject"] as? String,
                  let body = userInfo["body"] as? String,
                  let pdfData = userInfo["pdfData"] as? Data,
                  let fileName = userInfo["fileName"] as? String else {
                print("🔴 NotificationManager: Invalid ShowSupportEmail notification userInfo")
                return
            }
            block(subject, body, pdfData, fileName)
        }
    }
}

// MARK: - Notification Manager Extensions

extension NotificationManager {
    
    // MARK: - Debug Helpers
    
    static func logAllObservers() {
        print("📢 NotificationManager: Active notification names:")
        for notificationName in NotificationName.allCases {
            print("  - \(notificationName.rawValue)")
        }
    }
    
    // MARK: - Testing Helpers
    
    static func removeAllObservers(for object: Any) {
        for notificationName in NotificationName.allCases {
            removeObserver(object, for: notificationName)
        }
    }
    
    static func postTestNotification(_ notificationName: NotificationName, userInfo: [AnyHashable: Any]? = nil) {
        NotificationCenter.default.post(
            name: notificationName.notificationName,
            object: nil,
            userInfo: userInfo
        )
        print("📢 NotificationManager: Posted test notification - \(notificationName.rawValue)")
    }
}

// MARK: - Weak Reference Observer Wrapper

class WeakNotificationObserver {
    weak var observer: AnyObject?
    let notificationObserver: NSObjectProtocol
    
    init(observer: AnyObject, notificationObserver: NSObjectProtocol) {
        self.observer = observer
        self.notificationObserver = notificationObserver
    }
    
    deinit {
        NotificationCenter.default.removeObserver(notificationObserver)
    }
}