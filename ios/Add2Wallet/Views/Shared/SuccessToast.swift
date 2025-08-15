import SwiftUI

struct SuccessToast: View {
    let message: String
    let duration: Double
    @Binding var isPresented: Bool
    @State private var animationPhase = 0
    
    var body: some View {
        if isPresented {
            VStack(spacing: ThemeManager.Spacing.sm) {
                // Animated checkmark circle
                ZStack {
                    Circle()
                        .fill(ThemeManager.Colors.success)
                        .frame(width: 44, height: 44)
                        .scaleEffect(animationPhase == 0 ? 0.3 : 1.0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0), value: animationPhase)
                    
                    Image(systemName: "checkmark")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .scaleEffect(animationPhase < 2 ? 0.5 : 1.0)
                        .opacity(animationPhase < 1 ? 0 : 1)
                        .symbolEffect(.bounce, value: animationPhase)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0).delay(0.2), value: animationPhase)
                }
                
                // Success message
                Text(message)
                    .font(ThemeManager.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(ThemeManager.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .opacity(animationPhase < 2 ? 0 : 1)
                    .offset(y: animationPhase < 2 ? 20 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0).delay(0.3), value: animationPhase)
            }
            .padding(ThemeManager.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.large)
                    .fill(.thinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: 8)
            )
            .scaleEffect(animationPhase == 0 ? 0.8 : (animationPhase == 3 ? 0.9 : 1.0))
            .opacity(animationPhase == 3 ? 0 : 1)
            .animation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0), value: animationPhase)
            .onAppear {
                // Animation sequence
                withAnimation {
                    animationPhase = 1
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation {
                        animationPhase = 2
                    }
                }
                
                // Auto-dismiss after duration
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        animationPhase = 3
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isPresented = false
                        animationPhase = 0
                    }
                }
            }
        }
    }
}

struct SuccessToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let duration: Double
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresented {
                    SuccessToast(
                        message: message,
                        duration: duration,
                        isPresented: $isPresented
                    )
                    .padding(.top, ThemeManager.Spacing.lg)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .zIndex(1000)
                }
            }
    }
}

extension View {
    func successToast(
        isPresented: Binding<Bool>,
        message: String,
        duration: Double = 2.5
    ) -> some View {
        modifier(SuccessToastModifier(
            isPresented: isPresented,
            message: message,
            duration: duration
        ))
    }
}

#Preview {
    struct PreviewContainer: View {
        @State private var showingToast = false
        
        var body: some View {
            VStack {
                Button("Show Success Toast") {
                    showingToast = true
                }
                .themedPrimaryButton()
                
                Spacer()
            }
            .padding()
            .successToast(
                isPresented: $showingToast,
                message: "Pass added to Wallet successfully!"
            )
        }
    }
    
    return PreviewContainer()
}