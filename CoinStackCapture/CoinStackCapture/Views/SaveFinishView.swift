import SwiftUI

/// Final screen for saving the video and returning home
struct SaveFinishView: View {
    
    /// URL of the recorded video
    let videoURL: URL
    
    /// Session metadata
    let metadata: SessionMetadata
    
    /// Callback to return to home screen
    let onBackToHome: () -> Void
    
    /// Save state
    @State private var saveState: SaveState = .idle
    
    /// Whether to save to Photos
    @State private var saveToPhotos = false
    
    /// Animation state
    @State private var appeared = false
    @State private var showSuccess = false
    
    /// Storage manager
    private let storage = StorageManager.shared
    
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
                Spacer()
                    .frame(height: 60)
                
                // Success animation
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(hex: "4CAF50").opacity(0.3),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 40,
                                endRadius: 120
                            )
                        )
                        .frame(width: 240, height: 240)
                        .scaleEffect(showSuccess ? 1 : 0.5)
                        .opacity(showSuccess ? 1 : 0)
                    
                    // Checkmark circle
                    Circle()
                        .fill(Color(hex: "1B263B"))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Circle()
                                .stroke(Color(hex: "4CAF50"), lineWidth: 4)
                        )
                        .scaleEffect(showSuccess ? 1 : 0.8)
                    
                    // Checkmark
                    Image(systemName: "checkmark")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(Color(hex: "4CAF50"))
                        .scaleEffect(showSuccess ? 1 : 0)
                        .opacity(showSuccess ? 1 : 0)
                }
                .padding(.bottom, 40)
                
                // Title
                Text("Recording Complete")
                    .font(.custom("Avenir-Black", size: 28))
                    .foregroundColor(Color(hex: "E0E1DD"))
                    .opacity(appeared ? 1 : 0)
                
                Text("Your video is ready to save")
                    .font(.custom("Avenir-Medium", size: 16))
                    .foregroundColor(Color(hex: "778DA9"))
                    .padding(.top, 8)
                    .opacity(appeared ? 1 : 0)
                
                // Metadata card
                metadataCard
                    .padding(.top, 40)
                    .padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                
                Spacer()
                
                // Save options and buttons
                actionSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 30)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3)) {
                showSuccess = true
            }
        }
    }
    
    // MARK: - Subviews
    
    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Label("Recording Details", systemImage: "info.circle")
                .font(.custom("Avenir-Heavy", size: 15))
                .foregroundColor(Color(hex: "E0E1DD"))
            
            Divider()
                .background(Color(hex: "415A77").opacity(0.5))
            
            // Details
            MetadataRow(label: "Hand Used", value: metadata.handUsed == .left ? "Left" : "Right")
            MetadataRow(label: "Duration", value: formatDuration(metadata.recordingDurationSeconds))
            MetadataRow(label: "Resolution", value: metadata.videoResolution)
            MetadataRow(label: "Frame Rate", value: "\(metadata.frameRate) fps")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "1B263B").opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "415A77").opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var actionSection: some View {
        VStack(spacing: 20) {
            // Photos toggle
            Toggle(isOn: $saveToPhotos) {
                HStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "E0A458"))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save to Photos")
                            .font(.custom("Avenir-Heavy", size: 16))
                            .foregroundColor(Color(hex: "E0E1DD"))
                        
                        Text("Also export to your photo library")
                            .font(.custom("Avenir-Medium", size: 13))
                            .foregroundColor(Color(hex: "778DA9"))
                    }
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Color(hex: "E0A458")))
            .padding(.horizontal, 24)
            
            // Save button
            Button(action: saveVideo) {
                Group {
                    switch saveState {
                    case .idle:
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 18))
                            Text("Save Video")
                                .font(.custom("Avenir-Heavy", size: 18))
                        }
                        
                    case .saving:
                        HStack(spacing: 10) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "0D1B2A")))
                            Text("Saving...")
                                .font(.custom("Avenir-Heavy", size: 18))
                        }
                        
                    case .saved:
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                            Text("Saved!")
                                .font(.custom("Avenir-Heavy", size: 18))
                        }
                        
                    case .error(let message):
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 18))
                            Text(message)
                                .font(.custom("Avenir-Heavy", size: 16))
                                .lineLimit(1)
                        }
                    }
                }
                .foregroundColor(Color(hex: "0D1B2A"))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    LinearGradient(
                        colors: saveState == .error("") ?
                            [Color(hex: "FF5722"), Color(hex: "E64A19")] :
                            [Color(hex: "F4D58D"), Color(hex: "E0A458")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(saveState == .saving || saveState == .saved)
            .padding(.horizontal, 24)
            
            // Back to Home button
            Button(action: onBackToHome) {
                Text("Back to Home")
                    .font(.custom("Avenir-Heavy", size: 17))
                    .foregroundColor(Color(hex: "778DA9"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Actions
    
    private func saveVideo() {
        saveState = .saving
        
        Task {
            do {
                // Save to app storage
                _ = try storage.saveVideo(from: videoURL, with: metadata)
                
                // Optionally save to Photos
                if saveToPhotos {
                    try await storage.saveToPhotosLibrary(videoURL: videoURL)
                }
                
                await MainActor.run {
                    withAnimation {
                        saveState = .saved
                    }
                }
                
            } catch {
                await MainActor.run {
                    withAnimation {
                        saveState = .error("Save failed")
                    }
                }
            }
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs) seconds"
        }
    }
}

/// Row showing a metadata key-value pair
private struct MetadataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.custom("Avenir-Medium", size: 14))
                .foregroundColor(Color(hex: "778DA9"))
            
            Spacer()
            
            Text(value)
                .font(.custom("Avenir-Heavy", size: 14))
                .foregroundColor(Color(hex: "E0E1DD"))
        }
    }
}

/// States for the save process
private enum SaveState: Equatable {
    case idle
    case saving
    case saved
    case error(String)
}

#Preview {
    SaveFinishView(
        videoURL: URL(fileURLWithPath: "/tmp/test.mp4"),
        metadata: SessionMetadata.create(hand: .right, duration: 45.0),
        onBackToHome: {}
    )
}

