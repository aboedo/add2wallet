import UIKit
import SwiftUI
import RevenueCat

#if DEBUG
import RevenueCatUI

class DebugShakeDetector: ObservableObject {
    static let shared = DebugShakeDetector()
    
    @Published var isDebugOverlayPresented = false
    
    private init() {
        setupShakeDetection()
    }
    
    private func setupShakeDetection() {
        NotificationCenter.default.addObserver(
            forName: .deviceDidShakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showDebugOverlay()
        }
    }
    
    private func showDebugOverlay() {
        isDebugOverlayPresented = true
    }
}

// Extension to detect shake gestures
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShakeNotification, object: nil)
        }
    }
}

extension Notification.Name {
    static let deviceDidShakeNotification = Notification.Name("DeviceDidShake")
}

#endif