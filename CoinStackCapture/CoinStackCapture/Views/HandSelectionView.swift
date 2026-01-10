import SwiftUI

/// Screen for selecting which hand is being used for the coin stacking task
struct HandSelectionView: View {
    
    /// Callback when a hand is selected
    let onHandSelected: (HandSelection) -> Void
    
    /// Callback to go back
    let onBack: () -> Void
    
    /// Hover/pressed state for buttons
    @State private var leftPressed = false
    @State private var rightPressed = false
    @State private var appeared = false
    
    var body: some View {
        ZStack {
            // Background
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
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Back")
                                .font(.custom("Avenir-Medium", size: 17))
                        }
                        .foregroundColor(Color(hex: "778DA9"))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                Spacer()
                    .frame(height: 60)
                
                // Title
                VStack(spacing: 12) {
                    Image(systemName: "hand.raised.fingers.spread")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(Color(hex: "E0A458"))
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : -10)
                    
                    Text("Which hand?")
                        .font(.custom("Avenir-Black", size: 34))
                        .foregroundColor(Color(hex: "E0E1DD"))
                        .opacity(appeared ? 1 : 0)
                    
                    Text("Select the hand you'll use to stack coins")
                        .font(.custom("Avenir-Medium", size: 16))
                        .foregroundColor(Color(hex: "778DA9"))
                        .multilineTextAlignment(.center)
                        .opacity(appeared ? 1 : 0)
                }
                
                Spacer()
                    .frame(height: 80)
                
                // Hand selection buttons
                HStack(spacing: 24) {
                    // Left hand button
                    HandButton(
                        hand: .left,
                        isPressed: leftPressed,
                        onTap: { onHandSelected(.left) }
                    )
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : -30)
                    
                    // Right hand button
                    HandButton(
                        hand: .right,
                        isPressed: rightPressed,
                        onTap: { onHandSelected(.right) }
                    )
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : 30)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Info note
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                    Text("Make sure you have the matching template")
                        .font(.custom("Avenir-Medium", size: 14))
                }
                .foregroundColor(Color(hex: "778DA9").opacity(0.8))
                .padding(.bottom, 40)
                .opacity(appeared ? 1 : 0)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
    }
}

/// Button for selecting a hand
private struct HandButton: View {
    let hand: HandSelection
    let isPressed: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: {
            print("🖐️ Hand button tapped: \(hand == .left ? "Left" : "Right")")
            onTap()
        }) {
            VStack(spacing: 20) {
                // Hand icon
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(Color(hex: "E0E1DD"))
                    .scaleEffect(x: hand == .left ? -1 : 1, y: 1)
                
                // Label
                Text(hand == .left ? "Left" : "Right")
                    .font(.custom("Avenir-Heavy", size: 22))
                    .foregroundColor(Color(hex: "E0E1DD"))
                
                Text("Hand")
                    .font(.custom("Avenir-Medium", size: 16))
                    .foregroundColor(Color(hex: "778DA9"))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
        }
        .buttonStyle(HandButtonStyle())
    }
}

/// Custom button style for hand selection buttons with press animation
private struct HandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "1B263B"),
                                Color(hex: "0D1B2A")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                configuration.isPressed ?
                                    Color(hex: "E0A458") :
                                    Color(hex: "415A77").opacity(0.5),
                                lineWidth: configuration.isPressed ? 2 : 1
                            )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .shadow(
                color: configuration.isPressed ?
                    Color(hex: "E0A458").opacity(0.3) :
                    Color.black.opacity(0.2),
                radius: configuration.isPressed ? 15 : 10,
                y: configuration.isPressed ? 2 : 5
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    HandSelectionView(
        onHandSelected: { _ in },
        onBack: {}
    )
}

