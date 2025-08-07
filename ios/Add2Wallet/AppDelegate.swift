import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        NotificationCenter.default.post(
            name: NSNotification.Name("AppDidOpenURL"),
            object: nil,
            userInfo: ["url": url]
        )
        return true
    }
}
