import SwiftUI
import Combine

@MainActor
class ProgressViewModel: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var progressMessage: String = ""
    @Published var funnyPhrase: String = ""
    
    private var startTime: Date?
    private var timer: AnyCancellable?
    private let totalDuration: TimeInterval = 30.0 // 30 seconds total duration
    
    private let phrases: [String] = [
        "Sharpening digital scissors ✂️",
        "Teaching the pass to be classy 🧣",
        "Taming barcodes in the wild 🦓",
        "Politely asking pixels to line up 📐",
        "Squeezing the PDF into your Wallet 💼",
        "Convincing Apple to like this pass 🍏",
        "Adding just a pinch of magic ✨",
        "Enrolling pass in wallet etiquette school 🎓",
        "Ironing out the manifest wrinkles 🧺",
        "Signing with a very fancy pen 🖋️",
    ]
    
    // Discrete progress values - maximum 15 updates total for performance
    // Start at 3% for immediate feedback, then progress through remaining values
    private let discreteProgressValues: [Double] = [
        0.03, 0.07, 0.15, 0.23, 0.30, 0.40, 0.50, 0.55, 0.65, 0.73, 0.80, 0.85, 0.90, 0.95, 1.0
    ]
    
    private let progressSteps: [(progress: Double, message: String, minDuration: TimeInterval)] = [
        (0.15, "Analyzing PDF...", 3.0),
        (0.40, "Extracting barcodes...", 7.0),
        (0.65, "Processing metadata...", 8.0),
        (0.85, "Generating pass...", 7.0),
        (0.95, "Signing certificate...", 5.0)
    ]
    
    func startProgress() {
        print("🎯 ProgressViewModel: Starting progress animation")
        startTime = Date()
        progressMessage = "Analyzing PDF..."
        funnyPhrase = phrases.randomElement() ?? "Getting things ready..."
        
        // Immediately show 3% progress for instant feedback
        withAnimation(.easeInOut(duration: 0.3)) {
            progress = 0.03
        }
        
        // Use much less frequent updates - only every 1 second
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateProgress()
            }
    }
    
    func stopProgress() {
        timer?.cancel()
        timer = nil
        startTime = nil
        
        // Reset progress with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            progress = 0.0
            progressMessage = ""
            funnyPhrase = ""
        }
    }
    
    func completeProgress() {
        // Animate to 100% completion
        withAnimation(.easeInOut(duration: 0.3)) {
            progress = 1.0
            progressMessage = "Complete!"
        }
        
        // Reset after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.stopProgress()
        }
    }
    
    private func updateProgress() {
        guard let startTime = startTime else { return }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        // Calculate discrete progress based on time elapsed
        let timeRatio = min(1.0, elapsedTime / totalDuration)
        // Skip the first value (0.03) since we set it immediately on start
        let adjustedIndex = 1 + Int(timeRatio * Double(discreteProgressValues.count - 2))
        let newProgress = discreteProgressValues[min(adjustedIndex, discreteProgressValues.count - 1)]
        
        // Only update if progress actually changed (discrete values)
        guard newProgress != progress else { return }
        
        // Find current step message based on elapsed time
        var currentMessage = "Analyzing PDF..."
        var cumulativeTime: TimeInterval = 0
        
        for step in progressSteps {
            if elapsedTime >= cumulativeTime {
                currentMessage = step.message
                cumulativeTime += step.minDuration
            } else {
                break
            }
        }
        
        // Update with animation only when values actually change
        print("🎯 ProgressViewModel: Updating progress to \(newProgress) - \(currentMessage)")
        withAnimation(.easeInOut(duration: 0.5)) {
            self.progress = newProgress
            self.progressMessage = currentMessage
        }
        
        // Update funny phrase occasionally (every 3 seconds)
        if Int(elapsedTime) % 3 == 0 && elapsedTime > 0 {
            updateFunnyPhrase()
        }
    }
    
    private func updateFunnyPhrase() {
        var next = phrases.randomElement() ?? "Almost there..."
        if next == funnyPhrase {
            next = phrases.shuffled().first ?? next
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            funnyPhrase = next
        }
    }
    
    deinit {
        timer?.cancel()
    }
}