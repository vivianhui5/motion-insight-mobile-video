import SwiftUI

/// Landing screen introducing the coin stacking task and guiding patients to start
struct LandingView: View {
    
    /// Callback when user taps to start capture
    let onStartCapture: () -> Void
    
    /// Animation state for the coin icon
    @State private var coinAnimationOffset: CGFloat = 0
    @State private var showInstructions = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(hex: "0D1B2A"),
                    Color(hex: "1B263B"),
                    Color(hex: "415A77")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Subtle pattern overlay
            GeometryReader { geo in
                Path { path in
                    let spacing: CGFloat = 40
                    for x in stride(from: 0, through: geo.size.width, by: spacing) {
                        for y in stride(from: 0, through: geo.size.height, by: spacing) {
                            path.addEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
                        }
                    }
                }
                .fill(Color.white.opacity(0.03))
            }
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 80)
                
                // Animated coin stack icon
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "E0A458").opacity(0.3), .clear],
                                center: .center,
                                startRadius: 40,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                    
                    // Coin stack visualization
                    VStack(spacing: -8) {
                        ForEach(0..<4) { index in
                            CoinShape()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(hex: "F4D58D"),
                                            Color(hex: "E0A458"),
                                            Color(hex: "BF8B2E")
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 70, height: 20)
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
                                .offset(y: index == 0 ? coinAnimationOffset : 0)
                        }
                    }
                }
                .padding(.bottom, 40)
                
                // App title
                Text("Coin Stack")
                    .font(.custom("Avenir-Black", size: 42))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "E0E1DD"), Color(hex: "778DA9")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .tracking(2)
                
                Text("CAPTURE")
                    .font(.custom("Avenir-Medium", size: 18))
                    .foregroundColor(Color(hex: "778DA9"))
                    .tracking(8)
                    .padding(.top, 4)
                
                Spacer()
                    .frame(height: 60)
                
                // Instructions card
                VStack(alignment: .leading, spacing: 16) {
                    Label("What you'll need", systemImage: "checklist")
                        .font(.custom("Avenir-Heavy", size: 16))
                        .foregroundColor(Color(hex: "E0E1DD"))
                    
                    InstructionRow(
                        icon: "doc.text",
                        text: "Printed paper template with QR codes"
                    )
                    
                    InstructionRow(
                        icon: "hand.raised",
                        text: "Coins for the stacking task"
                    )
                    
                    InstructionRow(
                        icon: "light.max",
                        text: "Well-lit, stable surface"
                    )
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(hex: "1B263B").opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color(hex: "415A77").opacity(0.5), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 24)
                .opacity(showInstructions ? 1 : 0)
                .offset(y: showInstructions ? 0 : 20)
                
                Spacer()
                
                // Capture button
                Button(action: onStartCapture) {
                    HStack(spacing: 12) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 22, weight: .semibold))
                        
                        Text("Capture Video")
                            .font(.custom("Avenir-Heavy", size: 20))
                    }
                    .foregroundColor(Color(hex: "0D1B2A"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "F4D58D"), Color(hex: "E0A458")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: Color(hex: "E0A458").opacity(0.4), radius: 12, y: 6)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Coin bounce animation
        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: true)
        ) {
            coinAnimationOffset = -8
        }
        
        // Instructions fade in
        withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
            showInstructions = true
        }
    }
}

/// Single instruction row
private struct InstructionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color(hex: "E0A458"))
                .frame(width: 28)
            
            Text(text)
                .font(.custom("Avenir-Medium", size: 15))
                .foregroundColor(Color(hex: "778DA9"))
        }
    }
}

/// Custom coin shape
private struct CoinShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cornerRadius: CGFloat = 6
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return path
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    LandingView(onStartCapture: {})
}

