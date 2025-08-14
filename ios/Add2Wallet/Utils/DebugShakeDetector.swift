import UIKit
import SwiftUI
import RevenueCat

#if DEBUG
import RevenueCatUI

class DebugShakeDetector {
    static let shared = DebugShakeDetector()
    
    private var isDebugViewPresented = false
    
    private init() {
        setupShakeDetection()
    }
    
    private func setupShakeDetection() {
        NotificationCenter.default.addObserver(
            forName: .deviceDidShakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showDebugView()
        }
    }
    
    private func showDebugView() {
        guard !isDebugViewPresented else { return }
        
        isDebugViewPresented = true
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            
            let debugView = DebugMenuView {
                self.isDebugViewPresented = false
            }
            
            let hostingController = UIHostingController(rootView: debugView)
            hostingController.modalPresentationStyle = .pageSheet
            
            window.rootViewController?.present(hostingController, animated: true)
        }
    }
}

struct DebugMenuView: View {
    let onDismiss: () -> Void
    @State private var showingRevenueCatDebugger = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("🐛 Debug Menu")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                VStack(spacing: 16) {
                    Button(action: {
                        showingRevenueCatDebugger = true
                    }) {
                        HStack {
                            Image(systemName: "dollarsign.circle")
                            Text("RevenueCat Debugger")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .foregroundColor(.blue)
                    
                    Button(action: {
                        // Clear all app data for testing
                        clearAppData()
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear App Data")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .foregroundColor(.red)
                    
                    Button(action: {
                        // Reset RevenueCat cache
                        Purchases.shared.invalidateCustomerInfoCache()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Reset RevenueCat Cache")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .foregroundColor(.orange)
                }
                
                Spacer()
                
                Text("App User ID: \(Purchases.shared.appUserID)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingRevenueCatDebugger) {
            DebugRevenueCatView()
        }
    }
    
    private func clearAppData() {
        // Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        
        // Clear RevenueCat cache
        Purchases.shared.invalidateCustomerInfoCache()
        
        print("🗑️ App data cleared for testing")
    }
}

struct DebugRevenueCatView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var customerInfo: CustomerInfo?
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        SwiftUI.ProgressView("Loading RevenueCat data...")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        debugContent
                    }
                }
                .padding()
            }
            .navigationTitle("RevenueCat Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadCustomerInfo()
            }
        }
    }
    
    private var debugContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Customer Info Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Customer Info")
                    .font(.headline)
                
                Text("App User ID: \(Purchases.shared.appUserID)")
                    .font(.caption)
                    .textSelection(.enabled)
                
                if let customerInfo = customerInfo {
                    Text("Original App User ID: \(customerInfo.originalAppUserId)")
                        .font(.caption)
                        .textSelection(.enabled)
                    
                    Text("First Seen: \(DateFormatter.localizedString(from: customerInfo.firstSeen, dateStyle: .short, timeStyle: .short))")
                        .font(.caption)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Virtual Currencies Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Virtual Currencies")
                    .font(.headline)
                
                Button("Check Virtual Currencies") {
                    Task {
                        await checkVirtualCurrencies()
                    }
                }
                .foregroundColor(.blue)
                
                Text("Note: Virtual currencies will be checked via API")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Actions Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Debug Actions")
                    .font(.headline)
                
                Button("Refresh Customer Info") {
                    Task {
                        await loadCustomerInfo(forceRefresh: true)
                    }
                }
                .foregroundColor(.blue)
                
                Button("Invalidate Cache") {
                    Purchases.shared.invalidateCustomerInfoCache()
                }
                .foregroundColor(.orange)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private func loadCustomerInfo(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            if forceRefresh {
                Purchases.shared.invalidateCustomerInfoCache()
            }
            let info = try await Purchases.shared.customerInfo()
            await MainActor.run {
                self.customerInfo = info
            }
        } catch {
            print("Error loading customer info: \(error)")
        }
    }
    
    private func checkVirtualCurrencies() async {
        do {
            let virtualCurrencies = try await Purchases.shared.virtualCurrencies()
            print("🪙 Virtual Currencies:")
            for (currency, info) in virtualCurrencies.all {
                print("  \(currency): \(info.balance)")
            }
        } catch {
            print("Error fetching virtual currencies: \(error)")
        }
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