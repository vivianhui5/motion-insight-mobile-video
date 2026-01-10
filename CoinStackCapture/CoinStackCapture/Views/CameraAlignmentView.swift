import SwiftUI
import AVFoundation

/// Camera alignment and recording screen with QR code validation
struct CameraAlignmentView: View {
    
    /// Selected hand for this session
    let selectedHand: HandSelection
    
    /// Callback when recording is complete
    let onRecordingComplete: (URL, SessionMetadata) -> Void
    
    /// Callback to go back
    let onBack: () -> Void
    
    /// Camera manager
    @StateObject private var cameraManager = CameraManager()
    
    /// Whether camera permission is granted
    @State private var cameraPermissionGranted = false
    
    /// Whether to show permission denied alert
    @State private var showPermissionAlert = false
    
    /// Whether we're checking permission (initial state)
    @State private var isCheckingPermission = true
    
    var body: some View {
        ZStack {
            // Background - always black to prevent white flash
            Color.black.ignoresSafeArea()
            
            if isCheckingPermission {
                // Initial loading state while checking permissions
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "E0A458")))
                        .scaleEffect(1.5)
                    Text("Preparing camera...")
                        .font(.custom("Avenir-Medium", size: 16))
                        .foregroundColor(Color(hex: "778DA9"))
                }
            } else if cameraPermissionGranted {
                // Camera content
                GeometryReader { geometry in
                    ZStack {
                        // Camera preview - always present, shows black until session connects
                        CameraPreviewView(cameraManager: cameraManager)
                            .ignoresSafeArea()
                        
                        // Loading state overlay (shows while camera initializes)
                        if !cameraManager.isCameraReady {
                            ZStack {
                                Color.black
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "E0A458")))
                                        .scaleEffect(1.5)
                                    Text("Initializing camera...")
                                        .font(.custom("Avenir-Medium", size: 16))
                                        .foregroundColor(Color(hex: "778DA9"))
                                }
                            }
                            .ignoresSafeArea()
                        }
                        
                        // Alignment overlay (hidden during recording, only show when camera ready)
                        if !cameraManager.isRecording && cameraManager.isCameraReady {
                            AlignmentOverlayView(
                                alignmentState: cameraManager.alignmentState,
                                previewSize: geometry.size
                            )
                        }
                        
                        // UI overlay
                        VStack {
                            // Top bar
                            topBar
                            
                            Spacer()
                            
                            // Horizontal phone guidance (when not horizontal and not recording)
                            if !cameraManager.isDeviceHorizontal && !cameraManager.isRecording && cameraManager.isCameraReady {
                                horizontalGuidance
                            }
                            
                            // Feedback panel (hidden during recording)
                            if !cameraManager.isRecording && cameraManager.isCameraReady {
                                feedbackPanel
                            }
                            
                            // Recording indicator
                            if cameraManager.isRecording {
                                recordingIndicator
                            }
                            
                            // Bottom controls
                            if cameraManager.isCameraReady {
                                bottomControls
                            }
                        }
                    }
                }
            } else {
                // Permission request view
                permissionRequestView
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            checkCameraPermission()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .alert("Camera Access Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {
                onBack()
            }
        } message: {
            Text("Please enable camera access in Settings to record your coin stacking task.")
        }
    }
    
    // MARK: - Subviews
    
    private var topBar: some View {
        HStack {
            // Back button
            Button(action: {
                if cameraManager.isRecording {
                    cameraManager.stopRecording()
                }
                onBack()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            // Camera flip button
            if !cameraManager.isRecording {
                Button(action: {
                    cameraManager.toggleCamera()
                }) {
                    Image(systemName: "camera.rotate.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .padding(.trailing, 8)
            }
            
            // Hand indicator
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .scaleEffect(x: selectedHand == .left ? -1 : 1, y: 1)
                Text(selectedHand == .left ? "Left" : "Right")
                    .font(.custom("Avenir-Medium", size: 14))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
    
    private var horizontalGuidance: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.landscape")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Color(hex: "FFC107"))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Hold Phone Horizontally")
                    .font(.custom("Avenir-Heavy", size: 16))
                    .foregroundColor(.white)
                Text("Rotate for best video quality")
                    .font(.custom("Avenir-Medium", size: 13))
                    .foregroundColor(Color(hex: "778DA9"))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "FFC107").opacity(0.5), lineWidth: 1)
                )
        )
        .padding(.horizontal, 40)
        .padding(.bottom, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: cameraManager.isDeviceHorizontal)
    }
    
    private var feedbackPanel: some View {
        VStack(spacing: 12) {
            // Status icon
            Image(systemName: cameraManager.alignmentState.feedbackIcon)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(feedbackColor)
            
            // Status message
            Text(cameraManager.alignmentState.feedbackMessage)
                .font(.custom("Avenir-Heavy", size: 18))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            // Hint message (when available)
            if let hint = cameraManager.alignmentState.feedbackHint {
                Text(hint)
                    .font(.custom("Avenir-Medium", size: 14))
                    .foregroundColor(Color(hex: "778DA9"))
                    .multilineTextAlignment(.center)
            }
            
            // Distance indicator (when QR codes are detected and matched)
            if cameraManager.alignmentState.bothQRCodesDetected &&
               cameraManager.alignmentState.qrCodesMatchTemplate {
                DistanceIndicator(
                    distanceFeedback: cameraManager.alignmentState.distanceFeedback
                )
            }
            
            // Front camera indicator
            if cameraManager.isUsingFrontCamera {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                    Text("Front Camera (Mirrored)")
                        .font(.custom("Avenir-Medium", size: 12))
                }
                .foregroundColor(Color(hex: "2196F3"))
                .padding(.top, 4)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.7))
        )
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
    }
    
    private var feedbackColor: Color {
        if cameraManager.alignmentState.isReadyToRecord {
            return Color(hex: "4CAF50") // Green - ready!
        } else if cameraManager.alignmentState.bothQRCodesDetected {
            return Color(hex: "FFC107") // Yellow/amber - adjusting
        } else {
            return Color(hex: "778DA9") // Gray - searching
        }
    }
    
    private var recordingIndicator: some View {
        HStack(spacing: 12) {
            // Pulsing red dot
            Circle()
                .fill(Color.red)
                .frame(width: 14, height: 14)
                .modifier(PulsingModifier())
            
            // Timer
            Text(formatDuration(cameraManager.recordingDuration))
                .font(.custom("Avenir-Heavy", size: 24))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.7))
        )
        .padding(.bottom, 20)
    }
    
    private var bottomControls: some View {
        HStack {
            Spacer()
            
            // Record/Stop button
            Button(action: {
                if cameraManager.isRecording {
                    cameraManager.stopRecording()
                } else {
                    startRecording()
                }
            }) {
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    // Inner shape (circle for record, square for stop)
                    if cameraManager.isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red)
                            .frame(width: 32, height: 32)
                    } else {
                        Circle()
                            .fill(cameraManager.alignmentState.isReadyToRecord ?
                                  Color.red : Color.gray)
                            .frame(width: 64, height: 64)
                    }
                }
            }
            .disabled(!cameraManager.alignmentState.isReadyToRecord && !cameraManager.isRecording)
            
            Spacer()
        }
        .padding(.bottom, 40)
    }
    
    private var permissionRequestView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(Color(hex: "778DA9"))
            
            Text("Camera Access Needed")
                .font(.custom("Avenir-Heavy", size: 24))
                .foregroundColor(.white)
            
            Text("We need camera access to record your coin stacking task for medical assessment.")
                .font(.custom("Avenir-Medium", size: 16))
                .foregroundColor(Color(hex: "778DA9"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: checkCameraPermission) {
                Text("Grant Access")
                    .font(.custom("Avenir-Heavy", size: 18))
                    .foregroundColor(Color(hex: "0D1B2A"))
                    .frame(width: 200, height: 50)
                    .background(Color(hex: "E0A458"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 20)
        }
    }
    
    // MARK: - Helpers
    
    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("🔐 Permission status: \(status.rawValue)")
        
        switch status {
        case .authorized:
            print("🔐 Already authorized, setting up camera...")
            // Set state and start camera setup immediately
            cameraPermissionGranted = true
            isCheckingPermission = false
            // Start camera setup right away - the view is already loaded at this point
            cameraManager.setupCamera(for: selectedHand)
            
        case .notDetermined:
            print("🔐 Requesting permission...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    print("🔐 Permission response: \(granted)")
                    self.isCheckingPermission = false
                    if granted {
                        self.cameraPermissionGranted = true
                        // Start camera immediately after permission granted
                        self.cameraManager.setupCamera(for: self.selectedHand)
                    } else {
                        self.showPermissionAlert = true
                    }
                }
            }
            
        case .denied, .restricted:
            print("🔐 Permission denied or restricted")
            isCheckingPermission = false
            showPermissionAlert = true
            
        @unknown default:
            print("🔐 Unknown permission status")
            isCheckingPermission = false
            showPermissionAlert = true
        }
    }
    
    private func startRecording() {
        cameraManager.startRecording { url, metadata in
            if let url = url, let metadata = metadata {
                onRecordingComplete(url, metadata)
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

/// Distance indicator showing optimal camera position
private struct DistanceIndicator: View {
    let distanceFeedback: DistanceFeedback
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Rectangle()
                    .fill(barColor(for: index))
                    .frame(width: 30, height: 6)
                    .clipShape(Capsule())
            }
        }
    }
    
    private func barColor(for index: Int) -> Color {
        switch distanceFeedback {
        case .tooFar:
            return index == 0 ? Color(hex: "FFC107") : Color.gray.opacity(0.3)
        case .optimal:
            return index == 1 ? Color(hex: "4CAF50") : Color.gray.opacity(0.3)
        case .tooClose:
            return index == 2 ? Color(hex: "FF5722") : Color.gray.opacity(0.3)
        }
    }
}

/// Pulsing animation modifier
private struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

#Preview {
    CameraAlignmentView(
        selectedHand: .right,
        onRecordingComplete: { _, _ in },
        onBack: {}
    )
}
