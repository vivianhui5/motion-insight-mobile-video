import SwiftUI
import AVKit

/// SwiftUI wrapper for AVPlayerViewController
struct VideoPlayerView: UIViewControllerRepresentable {
    
    /// URL of the video to play
    let videoURL: URL
    
    /// Whether to auto-play when appearing
    var autoPlay: Bool = false
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: videoURL)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        
        // Style the controller
        controller.view.backgroundColor = .black
        
        if autoPlay {
            player.play()
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Update player if URL changes
        if uiViewController.player?.currentItem?.asset != AVAsset(url: videoURL) {
            uiViewController.player = AVPlayer(url: videoURL)
        }
    }
}

/// Custom video player with more control over appearance
struct CustomVideoPlayerView: View {
    
    /// URL of the video to play
    let videoURL: URL
    
    /// Player instance
    @State private var player: AVPlayer?
    
    /// Whether video is playing
    @State private var isPlaying = false
    
    /// Current playback time
    @State private var currentTime: TimeInterval = 0
    
    /// Total duration
    @State private var duration: TimeInterval = 0
    
    /// Time observer token
    @State private var timeObserver: Any?
    
    var body: some View {
        ZStack {
            // Video layer
            VideoPlayer(player: player)
                .disabled(true) // Disable default controls
            
            // Custom overlay
            VStack {
                Spacer()
                
                // Progress bar and controls
                VStack(spacing: 12) {
                    // Time labels
                    HStack {
                        Text(formatTime(currentTime))
                            .font(.custom("Avenir-Medium", size: 12))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Text(formatTime(duration))
                            .font(.custom("Avenir-Medium", size: 12))
                            .foregroundColor(.white)
                    }
                    
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 4)
                                .clipShape(Capsule())
                            
                            // Progress
                            Rectangle()
                                .fill(Color(hex: "E0A458"))
                                .frame(
                                    width: duration > 0 ?
                                        geometry.size.width * (currentTime / duration) :
                                        0,
                                    height: 4
                                )
                                .clipShape(Capsule())
                        }
                    }
                    .frame(height: 4)
                    
                    // Play/Pause button
                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding(20)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func setupPlayer() {
        player = AVPlayer(url: videoURL)
        
        // Get duration
        Task {
            if let asset = player?.currentItem?.asset {
                let duration = try? await asset.load(.duration)
                if let duration = duration {
                    await MainActor.run {
                        self.duration = duration.seconds
                    }
                }
            }
        }
        
        // Add time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
        }
        
        // Observe playback end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            isPlaying = false
            player?.seek(to: .zero)
        }
    }
    
    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }
    
    private func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

