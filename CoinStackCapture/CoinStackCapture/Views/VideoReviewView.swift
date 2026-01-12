import SwiftUI
import AVKit
import Combine

/// Observable class to manage video playback state
class VideoPlaybackManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var isLoading = true
    @Published var loadError: String?
    @Published var progress: Double = 0
    @Published var duration: TimeInterval = 0
    
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    
    func loadVideo(from url: URL) {
        print("🎥 Loading video from: \(url.path)")
        
        // Verify file exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            print("🎥 ERROR: Video file not found")
            DispatchQueue.main.async {
                self.loadError = "Video file not found"
                self.isLoading = false
            }
            return
        }
        
        // Check file size
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            print("🎥 Video file size: \(fileSize) bytes")
            if fileSize == 0 {
                DispatchQueue.main.async {
                    self.loadError = "Video file is empty"
                    self.isLoading = false
                }
                return
            }
        } catch {
            print("🎥 ERROR: Cannot read video file: \(error)")
            DispatchQueue.main.async {
                self.loadError = "Cannot read video file"
                self.isLoading = false
            }
            return
        }
        
        // Create asset and player
        let asset = AVAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        self.playerItem = item
        
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.actionAtItemEnd = .pause
        
        // Load duration asynchronously
        Task {
            do {
                let loadedDuration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(loadedDuration)
                
                guard durationSeconds.isFinite && durationSeconds > 0 else {
                    DispatchQueue.main.async {
                        self.loadError = "Invalid video duration"
                        self.isLoading = false
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.duration = durationSeconds
                    self.player = newPlayer
                    self.isLoading = false
                    self.setupTimeObserver()
                    self.setupEndObserver()
                    print("🎥 Video loaded, duration: \(durationSeconds)s")
                }
            } catch {
                DispatchQueue.main.async {
                    self.loadError = "Failed to load video: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func setupTimeObserver() {
        guard let player = player else { return }
        
        // Update progress every 0.1 seconds
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, self.duration > 0 else { return }
            let currentSeconds = CMTimeGetSeconds(time)
            if currentSeconds.isFinite {
                self.progress = currentSeconds / self.duration
            }
        }
    }
    
    private func setupEndObserver() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.isPlaying = false
            self.player?.seek(to: .zero)
            self.progress = 0
            print("🎥 Playback ended")
        }
    }
    
    func togglePlayback() {
        guard let player = player else {
            print("🎥 No player available")
            return
        }
        
        if isPlaying {
            player.pause()
            isPlaying = false
            print("🎥 Paused at progress: \(progress)")
        } else {
            if progress >= 0.99 {
                player.seek(to: .zero)
                progress = 0
            }
            player.play()
            isPlaying = true
            print("🎥 Playing from progress: \(progress)")
        }
    }
    
    func seekTo(progress: Double) {
        guard let player = player, duration > 0 else { return }
        
        let time = CMTime(seconds: duration * progress, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        self.progress = progress
    }
    
    func cleanup() {
        player?.pause()
        isPlaying = false
        
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        
        if let endObs = endObserver {
            NotificationCenter.default.removeObserver(endObs)
        }
        endObserver = nil
        
        player = nil
        playerItem = nil
        print("🎥 Cleanup complete")
    }
}

/// Screen for reviewing the recorded video before saving
struct VideoReviewView: View {
    
    /// URL of the recorded video
    let videoURL: URL
    
    /// Callback to retake the video
    let onRetake: () -> Void
    
    /// Callback when done reviewing
    let onDone: () -> Void
    
    /// Playback manager
    @StateObject private var playbackManager = VideoPlaybackManager()
    
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
                    if let error = playbackManager.loadError {
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
                    } else if playbackManager.isLoading {
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
                    } else if let player = playbackManager.player {
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
                if !playbackManager.isLoading && playbackManager.loadError == nil {
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
            playbackManager.loadVideo(from: videoURL)
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
        .onDisappear {
            playbackManager.cleanup()
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
                        .frame(width: geometry.size.width * playbackManager.progress, height: 6)
                    
                    // Scrubber handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.3), radius: 3)
                        .offset(x: geometry.size.width * playbackManager.progress - 8)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newProgress = min(max(0, value.location.x / geometry.size.width), 1)
                            playbackManager.seekTo(progress: newProgress)
                        }
                )
            }
            .frame(height: 20)
            .padding(.horizontal, 20)
            
            // Time labels and play button
            HStack {
                Text(formatTime(playbackManager.duration * playbackManager.progress))
                    .font(.custom("Avenir-Medium", size: 13))
                    .foregroundColor(Color(hex: "778DA9"))
                    .monospacedDigit()
                    .frame(width: 50, alignment: .leading)
                
                Spacer()
                
                // Play/Pause button
                Button(action: {
                    playbackManager.togglePlayback()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "1B263B"))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Circle()
                                    .stroke(Color(hex: "E0A458"), lineWidth: 2)
                            )
                        
                        Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(hex: "E0A458"))
                            .offset(x: playbackManager.isPlaying ? 0 : 2)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(formatTime(playbackManager.duration))
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
            // Done button - must be instant and always responsive
            Button(action: {
                print("✅ Looks Good button pressed - navigating immediately")
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Retake button
            Button(action: {
                print("🔄 Retake Video button pressed")
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }
    
    // MARK: - Helpers
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Container for video player - displays video without built-in controls
/// We use our own custom controls for better integration
private struct VideoPlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        // Disable built-in controls - we have our own
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
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
