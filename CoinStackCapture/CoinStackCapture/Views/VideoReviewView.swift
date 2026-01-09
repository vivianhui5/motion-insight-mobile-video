import SwiftUI
import AVKit

/// Screen for reviewing the recorded video before saving
struct VideoReviewView: View {
    
    /// URL of the recorded video
    let videoURL: URL
    
    /// Callback to retake the video
    let onRetake: () -> Void
    
    /// Callback when done reviewing
    let onDone: () -> Void
    
    /// AVPlayer instance
    @State private var player: AVPlayer?
    
    /// Player item for status observation
    @State private var playerItem: AVPlayerItem?
    
    /// Whether video is currently playing
    @State private var isPlaying = false
    
    /// Whether video is loading
    @State private var isLoading = true
    
    /// Whether there was an error loading the video
    @State private var loadError: String?
    
    /// Current playback progress (0-1)
    @State private var progress: Double = 0
    
    /// Video duration in seconds
    @State private var duration: TimeInterval = 0
    
    /// Time observer token
    @State private var timeObserver: Any?
    
    /// Animation state
    @State private var appeared = false
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                header
                
                // Video player
                ZStack {
                    if let error = loadError {
                        // Error state
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(Color(hex: "FF5722"))
                            Text("Failed to load video")
                                .font(.custom("Avenir-Heavy", size: 18))
                                .foregroundColor(.white)
                            Text(error)
                                .font(.custom("Avenir-Medium", size: 14))
                                .foregroundColor(Color(hex: "778DA9"))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16/9, contentMode: .fit)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(hex: "1B263B"))
                        )
                    } else if isLoading {
                        // Loading state
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "1B263B"))
                            .aspectRatio(16/9, contentMode: .fit)
                            .overlay(
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "E0A458")))
                                        .scaleEffect(1.2)
                                    Text("Loading video...")
                                        .font(.custom("Avenir-Medium", size: 14))
                                        .foregroundColor(Color(hex: "778DA9"))
                                }
                            )
                    } else if let player = player {
                        // Video player with controls
                        VideoPlayerContainer(player: player)
                            .aspectRatio(16/9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(hex: "415A77").opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.95)
                
                // Playback controls
                if !isLoading && loadError == nil {
                    playbackControls
                        .padding(.top, 24)
                        .opacity(appeared ? 1 : 0)
                }
                
                Spacer()
                
                // Action buttons
                actionButtons
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 30)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            loadVideo()
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
        .onDisappear {
            cleanup()
        }
    }
    
    // MARK: - Subviews
    
    private var header: some View {
        VStack(spacing: 8) {
            Text("Review Recording")
                .font(.custom("Avenir-Heavy", size: 24))
                .foregroundColor(Color(hex: "E0E1DD"))
            
            Text("Make sure the video captured your task clearly")
                .font(.custom("Avenir-Medium", size: 14))
                .foregroundColor(Color(hex: "778DA9"))
        }
        .padding(.top, 24)
    }
    
    private var playbackControls: some View {
        VStack(spacing: 16) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "415A77").opacity(0.3))
                        .frame(height: 6)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "E0A458"), Color(hex: "F4D58D")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 6)
                    
                    // Scrubber handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.3), radius: 3)
                        .offset(x: geometry.size.width * progress - 8)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newProgress = min(max(0, value.location.x / geometry.size.width), 1)
                            seekTo(progress: newProgress)
                        }
                )
            }
            .frame(height: 20)
            .padding(.horizontal, 20)
            
            // Time labels and play button
            HStack {
                Text(formatTime(duration * progress))
                    .font(.custom("Avenir-Medium", size: 13))
                    .foregroundColor(Color(hex: "778DA9"))
                    .monospacedDigit()
                    .frame(width: 50, alignment: .leading)
                
                Spacer()
                
                // Play/Pause button
                Button(action: togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "1B263B"))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Circle()
                                    .stroke(Color(hex: "E0A458"), lineWidth: 2)
                            )
                        
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(hex: "E0A458"))
                            .offset(x: isPlaying ? 0 : 2)
                    }
                }
                
                Spacer()
                
                Text(formatTime(duration))
                    .font(.custom("Avenir-Medium", size: 13))
                    .foregroundColor(Color(hex: "778DA9"))
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 16) {
            // Done button
            Button(action: {
                cleanup()
                onDone()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                    Text("Looks Good")
                        .font(.custom("Avenir-Heavy", size: 18))
                }
                .foregroundColor(Color(hex: "0D1B2A"))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "F4D58D"), Color(hex: "E0A458")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            
            // Retake button
            Button(action: {
                cleanup()
                onRetake()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18))
                    Text("Retake Video")
                        .font(.custom("Avenir-Heavy", size: 17))
                }
                .foregroundColor(Color(hex: "778DA9"))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(hex: "415A77"), lineWidth: 1.5)
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }
    
    // MARK: - Video Loading
    
    private func loadVideo() {
        // Verify file exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: videoURL.path) else {
            loadError = "Video file not found"
            isLoading = false
            return
        }
        
        // Check file size to ensure it's valid
        do {
            let attributes = try fileManager.attributesOfItem(atPath: videoURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            if fileSize == 0 {
                loadError = "Video file is empty"
                isLoading = false
                return
            }
        } catch {
            loadError = "Cannot read video file"
            isLoading = false
            return
        }
        
        // Create asset and player item
        let asset = AVAsset(url: videoURL)
        let item = AVPlayerItem(asset: asset)
        self.playerItem = item
        
        // Create player
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.actionAtItemEnd = .pause
        
        // Load asset properties asynchronously
        Task {
            do {
                // Load duration
                let loadedDuration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(loadedDuration)
                
                // Verify it's a valid duration
                guard durationSeconds.isFinite && durationSeconds > 0 else {
                    await MainActor.run {
                        loadError = "Invalid video duration"
                        isLoading = false
                    }
                    return
                }
                
                await MainActor.run {
                    self.duration = durationSeconds
                    self.player = newPlayer
                    self.isLoading = false
                    
                    // Set up time observer
                    setupTimeObserver()
                    
                    // Set up end observer
                    setupEndObserver()
                }
            } catch {
                await MainActor.run {
                    loadError = "Failed to load video: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func setupTimeObserver() {
        guard let player = player else { return }
        
        // Add time observer
        let interval = CMTime(seconds: 0.05, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [self] time in
            if duration > 0 {
                let currentSeconds = CMTimeGetSeconds(time)
                if currentSeconds.isFinite {
                    progress = currentSeconds / duration
                }
            }
        }
    }
    
    private func setupEndObserver() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            isPlaying = false
            player?.seek(to: .zero)
            progress = 0
        }
    }
    
    private func cleanup() {
        // Stop playback
        player?.pause()
        
        // Remove time observer
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        
        // Clear player
        player = nil
        playerItem = nil
    }
    
    private func togglePlayback() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
        } else {
            if progress >= 0.99 {
                player.seek(to: .zero)
                progress = 0
            }
            player.play()
        }
        isPlaying.toggle()
    }
    
    private func seekTo(progress: Double) {
        guard let player = player, duration > 0 else { return }
        
        let time = CMTime(seconds: duration * progress, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        self.progress = progress
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Container for video player that properly displays AVPlayer
private struct VideoPlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Update player reference if needed
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

#Preview {
    VideoReviewView(
        videoURL: URL(fileURLWithPath: "/tmp/test.mp4"),
        onRetake: {},
        onDone: {}
    )
}
