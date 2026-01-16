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
    
    /// Whether to show the retake recommendation dialog
    @State private var showRetakeDialog = false
    
    /// The recorded video URL pending review
    @State private var pendingVideoURL: URL?
    
    /// The pending session metadata
    @State private var pendingMetadata: SessionMetadata?
    
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
                            // Top bar - stays fixed, not rotated
                            topBar
                            
                            Spacer()
                            
                            // Orientation warnings (not rotated - shown in current orientation)
                            // Portrait mode warning
                            if !cameraManager.isDeviceHorizontal && !cameraManager.isRecording && cameraManager.isCameraReady {
                                horizontalGuidance
                            }
                            
                            // Wrong landscape orientation warning (charging port should be on RIGHT)
                            if cameraManager.isDeviceHorizontal && !cameraManager.isLandscapeRight && !cameraManager.isRecording && cameraManager.isCameraReady {
                                wrongLandscapeGuidance
                            }
                            
                            // Front camera warning - should always use rear camera
                            if cameraManager.isUsingFrontCamera && !cameraManager.isRecording && cameraManager.isCameraReady {
                                frontCameraWarning
                            }
                            
                            // Debug: log current state
                            let _ = {
                                print("🎯 UI State: horizontal=\(cameraManager.isDeviceHorizontal), landscapeRight=\(cameraManager.isLandscapeRight), recording=\(cameraManager.isRecording), ready=\(cameraManager.isCameraReady), frontCam=\(cameraManager.isUsingFrontCamera), rotation=\(cameraManager.uiRotationAngle)")
                                print("🎯 QR State: detected=\(cameraManager.alignmentState.bothQRCodesDetected), rollGood=\(cameraManager.alignmentState.isRollGood), centered=\(cameraManager.alignmentState.isCentered)")
                            }()
                            
                            // All guidance panels - show when in correct orientation
                            if cameraManager.isCorrectLandscape && !cameraManager.isRecording && cameraManager.isCameraReady && !cameraManager.isUsingFrontCamera {
                                // Main guidance content
                                VStack(spacing: 8) {
                                    // Viewing angle guidance
                                    if !cameraManager.isViewingAngleGood {
                                        viewingAngleGuidanceCompact
                                    }
                                    
                                    // Roll guidance
                                    if cameraManager.alignmentState.bothQRCodesDetected && 
                                       !cameraManager.alignmentState.isRollGood {
                                        rollGuidanceCompact
                                    }
                                    
                                    // Centering guidance
                                    if cameraManager.alignmentState.bothQRCodesDetected && 
                                       !cameraManager.alignmentState.isCentered {
                                        centeringGuidanceCompact
                                    }
                                    
                                    // Feedback panel - always show
                                    feedbackPanelCompact
                                    
                                    // Compact info panel
                                    if cameraManager.alignmentState.bothQRCodesDetected {
                                        compactInfoPanel
                                    }
                                }
                                .padding(.horizontal, 16)
                                .rotationEffect(.degrees(-cameraManager.uiRotationAngle))
                            }
                            
                            // Recording indicator - stays fixed at center
                            if cameraManager.isRecording {
                                recordingIndicator
                            }
                            
                            // Bottom controls - stays fixed
                            if cameraManager.isCameraReady {
                                bottomControls
                            }
                        }
                        
                        // Movement warning banner - positioned on right edge (horizontal top in landscape-right mode)
                        if cameraManager.isRecording, let warning = cameraManager.movementWarning {
                            HStack {
                                Spacer()
                                movementWarningBanner(warning: warning)
                                    .rotationEffect(.degrees(-cameraManager.uiRotationAngle))
                                    .padding(.trailing, 20)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .alert("Recording Quality", isPresented: $showRetakeDialog) {
            Button("Use This Video") {
                // Submit the video anyway
                if let url = pendingVideoURL, let metadata = pendingMetadata {
                    onRecordingComplete(url, metadata)
                }
            }
            Button("Retake Video", role: .cancel) {
                // Clear pending and let user record again
                pendingVideoURL = nil
                pendingMetadata = nil
            }
        } message: {
            Text("The camera moved quite a bit during recording. For best results, try to keep the phone steady.\n\nYou can still use this video, or record again.")
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
                Text("Charging port should be on the right side")
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
    
    /// Warning shown when phone is horizontal but in the wrong orientation (charging port on left instead of right)
    private var wrongLandscapeGuidance: some View {
        HStack(spacing: 12) {
            // Rotation arrow showing which way to flip
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(Color(hex: "FF5722"))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Horizontal the Other Way")
                    .font(.custom("Avenir-Heavy", size: 16))
                    .foregroundColor(.white)
                Text("Rotate 180° so charging port is on your RIGHT")
                    .font(.custom("Avenir-Medium", size: 13))
                    .foregroundColor(Color(hex: "778DA9"))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "FF5722"), lineWidth: 2)
                )
        )
        .padding(.horizontal, 40)
        .padding(.bottom, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: cameraManager.isLandscapeRight)
    }
    
    /// Warning shown when using front camera
    private var frontCameraWarning: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.rotate.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(Color(hex: "FF5722"))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Use Rear Camera")
                    .font(.custom("Avenir-Heavy", size: 16))
                    .foregroundColor(.white)
                Text("Tap the camera flip button to switch to rear camera")
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
                        .stroke(Color(hex: "FF5722").opacity(0.5), lineWidth: 1)
                )
        )
        .padding(.horizontal, 40)
        .padding(.bottom, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: cameraManager.isUsingFrontCamera)
    }
    
    private var viewingAngleGuidance: some View {
        HStack(spacing: 12) {
            Image(systemName: cameraManager.devicePitchAngle > 60 ? "arrow.up.forward" : "arrow.down.forward")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Color(hex: "2196F3"))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(cameraManager.devicePitchAngle > 60 ? "Don't Point Straight Down" : "Angle Phone Toward Paper")
                    .font(.custom("Avenir-Heavy", size: 16))
                    .foregroundColor(.white)
                Text(cameraManager.devicePitchAngle > 60 ? 
                     "Position phone to the side, not directly above" : 
                     "Tilt phone down toward the paper")
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
                        .stroke(Color(hex: "2196F3").opacity(0.5), lineWidth: 1)
                )
        )
        .padding(.horizontal, 40)
        .padding(.bottom, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: cameraManager.isViewingAngleGood)
    }
    
    /// Guidance for rotating the phone when QR code roll is outside ±5°
    private var rollGuidance: some View {
        let roll = cameraManager.alignmentState.qrCodeRoll
        let shouldRotateClockwise = roll < 0  // If roll is negative, rotate clockwise to fix
        
        return HStack(spacing: 16) {
            // Rotation arrow - shows which way to rotate
            // Phone is horizontal, so we show curved rotation arrows
            Image(systemName: shouldRotateClockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(Color(hex: "FF9800"))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Rotate Phone \(shouldRotateClockwise ? "Clockwise" : "Counter-Clockwise")")
                    .font(.custom("Avenir-Heavy", size: 16))
                    .foregroundColor(.white)
                Text("QR code is tilted \(abs(Int(roll)))° — straighten to ±5°")
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
                        .stroke(Color(hex: "FF9800").opacity(0.5), lineWidth: 1)
                )
        )
        .padding(.horizontal, 40)
        .padding(.bottom, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: cameraManager.alignmentState.qrCodeRoll)
    }
    
    /// Guidance for centering QR codes on screen
    private var centeringGuidance: some View {
        let center = cameraManager.alignmentState.qrCodesCenter
        let hTolerance = AlignmentState.horizontalCenterTolerance  // Stricter for horizontal
        let vTolerance = AlignmentState.verticalCenterTolerance
        let idealY = AlignmentState.idealVerticalCenter
        
        // Determine which directions need adjustment
        // If QR is on LEFT of frame, move camera LEFT to bring QR to center
        // If QR is on RIGHT of frame, move camera RIGHT to bring QR to center
        let needsMoveLeft = center.x < 0.5 - hTolerance
        let needsMoveRight = center.x > 0.5 + hTolerance
        let needsMoveDown = center.y < idealY - vTolerance  // QR is low, move camera down
        let needsMoveUp = center.y > idealY + vTolerance  // QR is high, move camera up
        
        // Choose the primary direction arrow
        let arrowName: String
        let directionText: String
        
        if needsMoveRight && needsMoveUp {
            arrowName = "arrow.up.right"
            directionText = "Move camera up and right"
        } else if needsMoveRight && needsMoveDown {
            arrowName = "arrow.down.right"
            directionText = "Move camera down and right"
        } else if needsMoveLeft && needsMoveUp {
            arrowName = "arrow.up.left"
            directionText = "Move camera up and left"
        } else if needsMoveLeft && needsMoveDown {
            arrowName = "arrow.down.left"
            directionText = "Move camera down and left"
        } else if needsMoveRight {
            arrowName = "arrow.right"
            directionText = "Move camera right"
        } else if needsMoveLeft {
            arrowName = "arrow.left"
            directionText = "Move camera left"
        } else if needsMoveUp {
            arrowName = "arrow.up"
            directionText = "Move camera up"
        } else if needsMoveDown {
            arrowName = "arrow.down"
            directionText = "Move camera down"
        } else {
            arrowName = "viewfinder"
            directionText = "Center QR codes"
        }
        
        return HStack(spacing: 16) {
            Image(systemName: arrowName)
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(Color(hex: "9C27B0"))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(directionText)
                    .font(.custom("Avenir-Heavy", size: 16))
                    .foregroundColor(.white)
                Text("Keep QR codes centered in frame")
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
                        .stroke(Color(hex: "9C27B0").opacity(0.5), lineWidth: 1)
                )
        )
        .padding(.horizontal, 40)
        .padding(.bottom, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: cameraManager.alignmentState.qrCodesCenter.x)
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
        .background(Color.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
    
    /// Shows movement warning banner during recording - positioned at top
    private func movementWarningBanner(warning: CameraManager.MovementWarning) -> some View {
        HStack(spacing: 12) {
            Image(systemName: warning.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color(hex: "FF9800"))
            
            Text(warning.message)
                .font(.custom("Avenir-Heavy", size: 18))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "FF9800"), lineWidth: 2)
                )
        )
        .padding(.horizontal, 20)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    /// Displays phone tilt (from sensors) and distance to QR code
    private var phoneTiltAndDistanceDisplay: some View {
        VStack(spacing: 12) {
            Text("Phone Orientation & Distance")
                .font(.custom("Avenir-Heavy", size: 14))
                .foregroundColor(.white)
            
            HStack(spacing: 24) {
                // Phone tilt/pitch (how much looking down)
                VStack(spacing: 4) {
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 20))
                        .rotationEffect(.degrees(cameraManager.devicePitchAngle))
                        .foregroundColor(Color(hex: "2196F3"))
                    Text("Tilt")
                        .font(.custom("Avenir-Medium", size: 11))
                        .foregroundColor(Color(hex: "778DA9"))
                    Text("\(Int(cameraManager.devicePitchAngle))°")
                        .font(.custom("Avenir-Heavy", size: 18))
                        .foregroundColor(Color(hex: "2196F3"))
                }
                
                // QR code roll (angle of QR top edge from horizontal)
                // Green if within ±5°, orange if needs rotation
                VStack(spacing: 4) {
                    let isRollGood = cameraManager.alignmentState.isRollGood
                    let rollColor = isRollGood ? Color(hex: "4CAF50") : Color(hex: "FF9800")
                    
                    ZStack {
                        Image(systemName: "rotate.right")
                            .font(.system(size: 20))
                            .rotationEffect(.degrees(Double(cameraManager.alignmentState.qrCodeRoll)))
                            .foregroundColor(rollColor)
                        
                        // Small indicator icon
                        if isRollGood {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "4CAF50"))
                                .offset(x: 12, y: -8)
                        }
                    }
                    
                    Text("QR Roll")
                        .font(.custom("Avenir-Medium", size: 11))
                        .foregroundColor(Color(hex: "778DA9"))
                    Text("\(Int(cameraManager.alignmentState.qrCodeRoll))°")
                        .font(.custom("Avenir-Heavy", size: 18))
                        .foregroundColor(rollColor)
                }
                
                // Distance to QR code
                VStack(spacing: 4) {
                    Image(systemName: "ruler")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "E0A458"))
                    Text("Distance")
                        .font(.custom("Avenir-Medium", size: 11))
                        .foregroundColor(Color(hex: "778DA9"))
                    if let distance = cameraManager.alignmentState.distanceToTopQR {
                        Text("\(Int(distance)) cm")
                            .font(.custom("Avenir-Heavy", size: 18))
                            .foregroundColor(Color(hex: "E0A458"))
                    } else {
                        Text("--")
                            .font(.custom("Avenir-Heavy", size: 18))
                            .foregroundColor(Color(hex: "778DA9"))
                    }
                }
            }
            
            // Viewing angle feedback
            HStack(spacing: 8) {
                Image(systemName: cameraManager.isViewingAngleGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(cameraManager.isViewingAngleGood ? Color(hex: "4CAF50") : Color(hex: "FF9800"))
                Text(cameraManager.isViewingAngleGood ? "Good angle (40-50°)" : (cameraManager.devicePitchAngle > 50 ? "Too steep (tilt up)" : "Too flat (tilt down)"))
                    .font(.custom("Avenir-Medium", size: 12))
                    .foregroundColor(cameraManager.isViewingAngleGood ? Color(hex: "4CAF50") : Color(hex: "FF9800"))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
    
    // MARK: - Compact Views for Landscape Mode
    
    /// Compact info panel showing roll, tilt, and distance - positioned at top-right
    private var compactInfoPanel: some View {
        VStack(spacing: 6) {
            // Roll
            HStack(spacing: 4) {
                let isRollGood = cameraManager.alignmentState.isRollGood
                let rollColor = isRollGood ? Color(hex: "4CAF50") : Color(hex: "FF9800")
                Image(systemName: isRollGood ? "checkmark.circle.fill" : "rotate.right")
                    .font(.system(size: 12))
                    .foregroundColor(rollColor)
                Text("\(Int(cameraManager.alignmentState.qrCodeRoll))°")
                    .font(.custom("Avenir-Heavy", size: 14))
                    .foregroundColor(rollColor)
            }
            
            // Tilt
            HStack(spacing: 4) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "2196F3"))
                Text("\(Int(cameraManager.devicePitchAngle))°")
                    .font(.custom("Avenir-Heavy", size: 14))
                    .foregroundColor(Color(hex: "2196F3"))
            }
            
            // Distance
            if let distance = cameraManager.alignmentState.distanceToTopQR {
                HStack(spacing: 4) {
                    Image(systemName: "ruler")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "E0A458"))
                    Text("\(Int(distance))cm")
                        .font(.custom("Avenir-Heavy", size: 14))
                        .foregroundColor(Color(hex: "E0A458"))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.8))
        )
    }
    
    /// Compact viewing angle guidance
    private var viewingAngleGuidanceCompact: some View {
        HStack(spacing: 8) {
            Image(systemName: cameraManager.devicePitchAngle > 50 ? "arrow.up" : "arrow.down")
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "2196F3"))
            Text(cameraManager.devicePitchAngle > 50 ? "Tilt up" : "Tilt down")
                .font(.custom("Avenir-Medium", size: 13))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.8))
                .overlay(Capsule().stroke(Color(hex: "2196F3").opacity(0.5), lineWidth: 1))
        )
    }
    
    /// Compact roll guidance
    private var rollGuidanceCompact: some View {
        let roll = cameraManager.alignmentState.qrCodeRoll
        let clockwise = roll < 0
        
        return HStack(spacing: 8) {
            Image(systemName: clockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "FF9800"))
            Text(clockwise ? "Rotate →" : "Rotate ←")
                .font(.custom("Avenir-Medium", size: 13))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.8))
                .overlay(Capsule().stroke(Color(hex: "FF9800").opacity(0.5), lineWidth: 1))
        )
    }
    
    /// Compact centering guidance
    private var centeringGuidanceCompact: some View {
        let center = cameraManager.alignmentState.qrCodesCenter
        let hTolerance = AlignmentState.horizontalCenterTolerance  // Stricter for horizontal
        let vTolerance = AlignmentState.verticalCenterTolerance
        let idealY = AlignmentState.idealVerticalCenter // 0.33 - bottom 2/3 of screen
        
        // If QR is on LEFT of frame (center.x < 0.5), move camera LEFT to bring QR to center
        // If QR is on RIGHT of frame (center.x > 0.5), move camera RIGHT to bring QR to center
        let needsLeft = center.x < 0.5 - hTolerance
        let needsRight = center.x > 0.5 + hTolerance
        // Use idealY (0.33) instead of 0.5 - QR codes should be in bottom 2/3
        // If QR is too low (center.y < idealY), move camera DOWN to bring QR up
        let needsDown = center.y < idealY - vTolerance
        let needsUp = center.y > idealY + vTolerance
        
        let arrowName: String
        if needsRight && needsUp { arrowName = "arrow.up.right" }
        else if needsRight && needsDown { arrowName = "arrow.down.right" }
        else if needsLeft && needsUp { arrowName = "arrow.up.left" }
        else if needsLeft && needsDown { arrowName = "arrow.down.left" }
        else if needsRight { arrowName = "arrow.right" }
        else if needsLeft { arrowName = "arrow.left" }
        else if needsUp { arrowName = "arrow.up" }
        else if needsDown { arrowName = "arrow.down" }
        else { arrowName = "viewfinder" }
        
        return HStack(spacing: 8) {
            Image(systemName: arrowName)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "9C27B0"))
            Text("Move camera")
                .font(.custom("Avenir-Medium", size: 13))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.8))
                .overlay(Capsule().stroke(Color(hex: "9C27B0").opacity(0.5), lineWidth: 1))
        )
    }
    
    /// Compact feedback panel
    private var feedbackPanelCompact: some View {
        HStack(spacing: 10) {
            Image(systemName: cameraManager.alignmentState.feedbackIcon)
                .font(.system(size: 20))
                .foregroundColor(feedbackColor)
            
            Text(cameraManager.alignmentState.feedbackMessage)
                .font(.custom("Avenir-Heavy", size: 14))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.8))
        )
    }
    
    private var bottomControls: some View {
        HStack {
            Spacer()
            
            // Record/Stop button - always enabled so user can record even if alignment isn't perfect
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
                    // Visual indicator: red when aligned, orange when not (but still tappable)
                    if cameraManager.isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red)
                            .frame(width: 32, height: 32)
                    } else {
                        Circle()
                            .fill(cameraManager.alignmentState.isReadyToRecord ?
                                  Color.red : Color.orange)
                            .frame(width: 64, height: 64)
                    }
                }
            }
            // Button is always enabled - user can record anytime
            
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
                // Check if recording had excessive movement
                if cameraManager.recordingHadExcessiveMovement {
                    // Store pending video and show retake dialog
                    pendingVideoURL = url
                    pendingMetadata = metadata
                    showRetakeDialog = true
                } else {
                    // Good recording, proceed directly
                    onRecordingComplete(url, metadata)
                }
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

