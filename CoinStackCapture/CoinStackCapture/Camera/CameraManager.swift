@preconcurrency import AVFoundation
import UIKit
import Vision
import CoreMotion

/// Manages camera session, preview, and frame processing for QR code detection
@MainActor
class CameraManager: NSObject, ObservableObject {

    // MARK: - Distance Calculation Constants
    
    /// Known QR code size in centimeters
    private static let qrCodeSizeCm: Double = 6.0
    
    /// Approximate focal length in pixels (for iPhone at 1920x1080)
    /// iPhone wide camera ~26mm equivalent, sensor ~4.8mm
    /// focal_pixels ≈ image_width * focal_mm / sensor_width_mm ≈ 1920 * 4 / 4.8 ≈ 1600
    private static let focalLengthPixels: Double = 1600.0
    
    // MARK: - Temporal Smoothing for QR Detection
    
    /// History of QR detection states for temporal smoothing (reduces flickering)
    /// Each entry is (timestamp, wasDetected)
    private var detectionHistory: [(timestamp: Date, detected: Bool, corners: [[CGPoint]], distance: CGFloat?, roll: CGFloat)] = []
    
    /// Time window for temporal smoothing (0.5 seconds)
    private static let smoothingWindowSeconds: TimeInterval = 0.5
    
    /// Threshold for considering QR as detected (majority of recent frames)
    private static let detectionThreshold: Double = 0.5
    
    // MARK: - Published Properties
    
    /// Current alignment state based on detected QR codes
    @Published var alignmentState = AlignmentState()
    
    /// Whether the camera session is running
    @Published var isSessionRunning = false
    
    /// Whether the camera session is fully configured and ready to display
    @Published var isCameraReady = false
    
    /// Error message if camera setup fails
    @Published var errorMessage: String?
    
    /// Whether recording is in progress
    @Published var isRecording = false
    
    /// Recording duration in seconds
    @Published var recordingDuration: TimeInterval = 0
    
    /// Whether the device is in landscape orientation (horizontal)
    @Published var isDeviceHorizontal = false
    
    /// Whether the device is in the correct landscape orientation
    /// For this app, we expect landscape-right (charging port on RIGHT side when viewing screen)
    @Published var isCorrectLandscape = false
    
    /// Current landscape mode: true = landscape-right (correct), false = landscape-left (wrong)
    @Published var isLandscapeRight = false
    
    /// Current device tilt angle (degrees from horizontal)
    @Published var deviceTiltAngle: Double = 0
    
    /// Current device pitch angle (how much it's tilted forward/looking down)
    /// 0 = looking straight ahead, -90 = looking straight down (bird's eye)
    @Published var devicePitchAngle: Double = 0
    
    /// Whether the viewing angle is good (not too flat/bird's eye view)
    /// Phone should be angled to look at paper from the side, not directly above
    @Published var isViewingAngleGood = true
    
    /// Rotation angle for UI elements to match landscape orientation (degrees)
    /// 90 = landscape-right, -90 = landscape-left
    @Published var uiRotationAngle: Double = 0
    
    /// Whether using front camera
    @Published var isUsingFrontCamera = false
    
    // MARK: - Movement Tracking During Recording
    
    /// Current movement warning to show user during recording
    @Published var movementWarning: MovementWarning?
    
    /// Whether the recording had excessive movement overall
    @Published var recordingHadExcessiveMovement = false
    
    /// Movement warning types
    enum MovementWarning: Equatable {
        case drifting
        case tooMuchMovement
        case qrCodeLost
        case tooFar
        case tooClose
        
        var message: String {
            switch self {
            case .drifting: return "Keep QR code in blue box"
            case .tooMuchMovement: return "Hold steady — too much movement"
            case .qrCodeLost: return "QR code lost — keep in frame"
            case .tooFar: return "Move closer (60-75cm)"
            case .tooClose: return "Move back (60-75cm)"
            }
        }
        
        var icon: String {
            switch self {
            case .drifting: return "viewfinder"
            case .tooMuchMovement: return "exclamationmark.triangle"
            case .qrCodeLost: return "viewfinder"
            case .tooFar: return "arrow.down.to.line"
            case .tooClose: return "arrow.up.to.line"
            }
        }
    }
    
    /// History of QR code centers during recording for movement analysis
    private var recordingMovementHistory: [(timestamp: Date, center: CGPoint)] = []
    
    /// Number of frames where QR was lost during recording
    private var framesWithQRLost: Int = 0
    
    /// Total frames during recording
    private var totalRecordingFrames: Int = 0
    
    /// Timestamp when the last warning was shown (for minimum display duration)
    private var lastWarningTime: Date?
    
    /// Minimum duration to show a warning (seconds)
    private static let warningMinDisplayDuration: TimeInterval = 1.5
    
    /// Movement threshold (normalized coordinates) - movements larger than this trigger warnings
    /// More sensitive: 0.012 (was 0.02)
    private static let movementWarningThreshold: CGFloat = 0.012
    
    /// Movement threshold for "excessive" overall - if average movement exceeds this, recommend retake
    /// More sensitive: 0.008 (was 0.015)
    private static let excessiveMovementThreshold: CGFloat = 0.008
    
    // MARK: - Camera Properties
    
    /// The AVCaptureSession for camera input
    nonisolated let captureSession = AVCaptureSession()
    
    /// Video output for recording
    private var videoOutput: AVCaptureMovieFileOutput?
    
    /// Video data output for frame processing
    private var videoDataOutput: AVCaptureVideoDataOutput?
    
    /// Current video input
    private var currentVideoInput: AVCaptureDeviceInput?
    
    /// The currently selected hand
    private var selectedHand: HandSelection = .left
    
    /// Timer for recording duration
    private var recordingTimer: Timer?
    
    /// Recording start time
    private var recordingStartTime: Date?
    
    /// Completion handler for recording
    private var recordingCompletion: ((URL?, SessionMetadata?) -> Void)?
    
    /// Preview layer for displaying camera feed
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    /// Motion manager for device orientation
    private let motionManager = CMMotionManager()
    
    // MARK: - Queue
    
    /// Serial queue for camera operations
    private let sessionQueue = DispatchQueue(label: "com.coinstackcapture.camera.session")
    
    /// Queue for video processing
    private let videoProcessingQueue = DispatchQueue(label: "com.coinstackcapture.camera.processing")
    
    // MARK: - Setup
    
    /// Starts motion updates for device orientation detection
    func startMotionUpdates() {
        // Default to allowing recording
        isDeviceHorizontal = true
        isViewingAngleGood = true
        isCorrectLandscape = true
        
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion, error == nil else { return }
            
            let gravity = motion.gravity
            
            // Device is in landscape when tilted to the side more than up/down
            let isLandscape = abs(gravity.x) > abs(gravity.y)
            let tiltAngle = atan2(gravity.y, abs(gravity.x)) * 180 / .pi
            
            self.deviceTiltAngle = tiltAngle
            self.isDeviceHorizontal = isLandscape
            
            // Detect landscape orientation
            // When viewing the screen with phone horizontal:
            // gravity.x < 0 means device is rotated with charging port on RIGHT (correct for this app)
            // gravity.x > 0 means device is rotated with charging port on LEFT (wrong)
            let landscapeRight = gravity.x < 0
            self.isLandscapeRight = landscapeRight
            self.isCorrectLandscape = isLandscape && landscapeRight
            
            // Calculate UI rotation angle for overlays to make them readable
            // When charging port is on RIGHT (gravity.x < 0): rotate UI -90° so text reads correctly
            // When charging port is on LEFT (gravity.x > 0): rotate UI +90°
            if isLandscape {
                self.uiRotationAngle = landscapeRight ? -90 : 90
            } else {
                // Portrait - no rotation needed but show warning
                self.uiRotationAngle = 0
            }
            
            // Calculate pitch angle (how much the phone is looking down)
            // gravity.z: -1 = looking straight down (bird's eye), 0 = looking straight ahead
            // Convert to degrees: 0 = straight ahead, -90 = straight down
            let pitchAngle = asin(-gravity.z) * 180 / .pi
            self.devicePitchAngle = pitchAngle
            
            // Good viewing angle: phone should be tilted 40-50° down
            // This ensures consistent framing for video capture
            let isTooFlat = pitchAngle > 50  // Looking too straight down
            let isTooStraight = pitchAngle < 40  // Not tilted enough
            self.isViewingAngleGood = !isTooFlat && !isTooStraight
        }
    }
    
    func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
    
    /// Configures and starts the camera session
    func setupCamera(for hand: HandSelection, useFrontCamera: Bool = false) {
        print("📷 setupCamera called - hand: \(hand), frontCamera: \(useFrontCamera)")
        self.selectedHand = hand
        self.isUsingFrontCamera = useFrontCamera
        self.isCameraReady = false
        self.errorMessage = nil
        
        // Start motion updates for orientation detection
        startMotionUpdates()
        
        let session = captureSession
        sessionQueue.async {
            // Stop if already running
            if session.isRunning {
                print("📷 Session already running, stopping first...")
                session.stopRunning()
            }
            
            // Remove all existing inputs/outputs
            for input in session.inputs {
                session.removeInput(input)
            }
            for output in session.outputs {
                session.removeOutput(output)
            }
            
            self.configureSession(session: session, useFrontCamera: useFrontCamera)
        }
    }
    
    /// Toggle between front and back camera
    func toggleCamera() {
        let newUseFront = !isUsingFrontCamera
        
        Task { @MainActor in
            self.isUsingFrontCamera = newUseFront
            self.isCameraReady = false
        }
        
        let session = captureSession
        sessionQueue.async {
            self.reconfigureCamera(session: session, useFrontCamera: newUseFront)
        }
    }
    
    /// Reconfigures camera for different position (front/back)
    nonisolated private func reconfigureCamera(session: AVCaptureSession, useFrontCamera: Bool) {
        session.beginConfiguration()
        
        // Remove current input
        for input in session.inputs {
            session.removeInput(input)
        }
        
        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            Task { @MainActor in
                self.errorMessage = useFrontCamera ? "Front camera not available" : "Rear camera not available"
                self.isCameraReady = true
            }
            session.commitConfiguration()
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            
            // Configure device
            try videoDevice.lockForConfiguration()
            if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoDevice.exposureMode = .continuousAutoExposure
            }
            if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoDevice.focusMode = .continuousAutoFocus
            }
            videoDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            videoDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            videoDevice.unlockForConfiguration()
            
            // Mirror video for front camera
            if useFrontCamera {
                if let connection = session.outputs.compactMap({ $0 as? AVCaptureVideoDataOutput }).first?.connection(with: .video) {
                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = true
                    }
                }
                if let movieConnection = session.outputs.compactMap({ $0 as? AVCaptureMovieFileOutput }).first?.connection(with: .video) {
                    if movieConnection.isVideoMirroringSupported {
                        movieConnection.isVideoMirrored = true
                    }
                }
            }
            
        } catch {
            Task { @MainActor in
                self.errorMessage = "Failed to configure camera: \(error.localizedDescription)"
            }
        }
        
        session.commitConfiguration()
        
        // Small delay to ensure configuration is applied
        Thread.sleep(forTimeInterval: 0.15)
        
        Task { @MainActor in
            self.isCameraReady = true
        }
    }
    
    /// Configures the capture session (runs on sessionQueue)
    nonisolated private func configureSession(session: AVCaptureSession, useFrontCamera: Bool = false) {
        print("📷 configureSession starting...")
        
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080
        
        // Add video input
        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            print("📷 ERROR: Camera not available")
            session.commitConfiguration()
            Task { @MainActor in
                self.errorMessage = useFrontCamera ? "Front camera not available" : "Rear camera not available"
                self.isCameraReady = true // Allow UI to show error
            }
            return
        }
        
        print("📷 Got video device: \(videoDevice.localizedName)")
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                print("📷 Added video input")
            }
            
            // Configure camera settings
            try videoDevice.lockForConfiguration()
            if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoDevice.exposureMode = .continuousAutoExposure
            }
            if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoDevice.focusMode = .continuousAutoFocus
            }
            // Set frame rate to 30fps
            videoDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            videoDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            videoDevice.unlockForConfiguration()
            
        } catch {
            print("📷 ERROR: Failed to configure: \(error)")
            session.commitConfiguration()
            Task { @MainActor in
                self.errorMessage = "Failed to configure camera: \(error.localizedDescription)"
                self.isCameraReady = true // Allow UI to show error
            }
            return
        }
        
        // Add video data output for QR code detection
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: videoProcessingQueue)
        dataOutput.alwaysDiscardsLateVideoFrames = true
        // Use BGRA for better Vision compatibility
        dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        if session.canAddOutput(dataOutput) {
            session.addOutput(dataOutput)
        }
        
        // Add movie file output for recording
        let movieOutput = AVCaptureMovieFileOutput()
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            
            // Disable audio
            if let audioConnection = movieOutput.connection(with: .audio) {
                audioConnection.isEnabled = false
            }
        }
        
        // Apply mirroring for front camera
        if useFrontCamera {
            if let connection = dataOutput.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
            if let movieConnection = movieOutput.connection(with: .video) {
                if movieConnection.isVideoMirroringSupported {
                    movieConnection.isVideoMirrored = true
                }
            }
        }
        
        session.commitConfiguration()
        
        // Start session
        session.startRunning()
        
        // Wait for session to fully start
        var attempts = 0
        while !session.isRunning && attempts < 10 {
            Thread.sleep(forTimeInterval: 0.05)
            attempts += 1
        }
        
        let isRunning = session.isRunning
        print("📷 Session configured, isRunning: \(isRunning)")
        Task { @MainActor in
            self.videoDataOutput = dataOutput
            self.videoOutput = movieOutput
            self.isSessionRunning = isRunning
            print("📷 Session state updated, waiting for preview...")
            // Small additional delay to ensure preview layer is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                print("📷 Camera ready!")
                self.isCameraReady = true
            }
        }
    }
    
    /// Creates the preview layer
    nonisolated func createPreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }
    
    /// Stops the camera session
    func stopSession() {
        stopMotionUpdates()
        let session = captureSession
        sessionQueue.async {
            session.stopRunning()
            Task { @MainActor in
                self.isSessionRunning = false
                self.isCameraReady = false
            }
        }
    }
    
    // MARK: - Recording
    
    /// Starts video recording
    func startRecording(completion: @escaping (URL?, SessionMetadata?) -> Void) {
        guard let movieOutput = videoOutput,
              !isRecording,
              isCameraReady else {
            print("📷 Cannot start recording - output: \(videoOutput != nil), recording: \(isRecording), ready: \(isCameraReady)")
            return
        }
        
        // Check for valid video connection
        guard let connection = movieOutput.connection(with: .video),
              connection.isActive else {
            print("📷 Cannot start recording - no active video connection")
            return
        }
        
        self.recordingCompletion = completion
        
        // Create temp file URL
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "coinstack_recording_\(Date().timeIntervalSince1970).mp4"
        let outputURL = tempDir.appendingPathComponent(filename)
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        // Set video orientation based on device orientation
        if connection.isVideoOrientationSupported {
            // For landscape recording
            connection.videoOrientation = .landscapeRight
        }
        
        // Start recording
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        
        isRecording = true
        recordingStartTime = Date()
        recordingDuration = 0
        
        // Reset movement tracking
        recordingMovementHistory.removeAll()
        framesWithQRLost = 0
        totalRecordingFrames = 0
        movementWarning = nil
        lastWarningTime = nil
        recordingHadExcessiveMovement = false
        
        // Start timer on main thread
        let startTime = Date()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    /// Stops video recording
    func stopRecording() {
        guard let movieOutput = videoOutput,
              isRecording else { return }
        
        movieOutput.stopRecording()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Analyze recording quality
        analyzeRecordingQuality()
        
        // Clear warning
        movementWarning = nil
    }
    
    /// Analyzes the recording for excessive movement
    private func analyzeRecordingQuality() {
        // Check if too many frames had QR lost
        let lostRatio = totalRecordingFrames > 0 ? Double(framesWithQRLost) / Double(totalRecordingFrames) : 0
        
        // Calculate average movement between frames
        var totalMovement: CGFloat = 0
        var movementCount = 0
        
        for i in 1..<recordingMovementHistory.count {
            let prev = recordingMovementHistory[i - 1].center
            let curr = recordingMovementHistory[i].center
            let movement = hypot(curr.x - prev.x, curr.y - prev.y)
            totalMovement += movement
            movementCount += 1
        }
        
        let avgMovement = movementCount > 0 ? totalMovement / CGFloat(movementCount) : 0
        
        // Recording had excessive movement if:
        // - More than 15% of frames had QR lost
        // - OR average movement per frame exceeds threshold
        recordingHadExcessiveMovement = lostRatio > 0.15 || avgMovement > CameraManager.excessiveMovementThreshold
        
        print("📊 Recording quality: lost=\(String(format: "%.1f", lostRatio * 100))%, avgMovement=\(String(format: "%.4f", avgMovement)), excessive=\(recordingHadExcessiveMovement)")
    }
    
    /// Processes QR codes during recording to track movement
    private func processQRCodesDuringRecording(_ observations: [VNBarcodeObservation]) {
        totalRecordingFrames += 1
        
        // Extract QR code positions
        var allCorners: [[CGPoint]] = []
        
        for observation in observations {
            let tl = observation.topLeft
            let tr = observation.topRight
            let br = observation.bottomRight
            let bl = observation.bottomLeft
            
            guard !tl.x.isNaN && !tl.y.isNaN,
                  !tr.x.isNaN && !tr.y.isNaN,
                  !br.x.isNaN && !br.y.isNaN,
                  !bl.x.isNaN && !bl.y.isNaN else {
                continue
            }
            
            let rawCornerPoints = [
                CGPoint(x: CGFloat(tl.x), y: CGFloat(tl.y)),
                CGPoint(x: CGFloat(tr.x), y: CGFloat(tr.y)),
                CGPoint(x: CGFloat(br.x), y: CGFloat(br.y)),
                CGPoint(x: CGFloat(bl.x), y: CGFloat(bl.y))
            ]
            allCorners.append(rawCornerPoints)
        }
        
        let qrDetected = allCorners.count >= 2
        
        if !qrDetected {
            framesWithQRLost += 1
            // Only warn about QR lost if it persists
            if framesWithQRLost > 5 {
                movementWarning = .qrCodeLost
                lastWarningTime = Date()
            }
            return
        }
        
        // Reset QR lost counter since we found QR codes
        framesWithQRLost = 0
        
        // Calculate distance during recording
        let imageSize = CGSize(width: 1920, height: 1080)
        var currentDistance: CGFloat = 0
        if let firstCorners = allCorners.first {
            currentDistance = CGFloat(calculateDistanceToCm(corners: firstCorners, imageSize: imageSize))
        }
        
        // Calculate center of all QR codes
        var totalX: CGFloat = 0
        var totalY: CGFloat = 0
        var pointCount: CGFloat = 0
        
        for corners in allCorners {
            for corner in corners {
                totalX += corner.x
                totalY += corner.y
                pointCount += 1
            }
        }
        
        let currentCenter = CGPoint(
            x: totalX / pointCount,
            y: totalY / pointCount
        )
        
        let now = Date()
        
        // Check movement against recent history (compare to average of last few frames for stability)
        let recentEntries = recordingMovementHistory.suffix(3)
        if recentEntries.count >= 2 {
            // Calculate movement from average of recent positions
            let avgPrevX = recentEntries.dropLast().map { $0.center.x }.reduce(0, +) / CGFloat(recentEntries.count - 1)
            let avgPrevY = recentEntries.dropLast().map { $0.center.y }.reduce(0, +) / CGFloat(recentEntries.count - 1)
            
            let movement = CGPoint(
                x: currentCenter.x - avgPrevX,
                y: currentCenter.y - avgPrevY
            )
            let movementMagnitude = hypot(movement.x, movement.y)
            
            // Check if we should show a new warning or update existing one
            if movementMagnitude > CameraManager.movementWarningThreshold {
                // Set warning and record the time
                let newWarning: MovementWarning
                if movementMagnitude > CameraManager.movementWarningThreshold * 2.0 {
                    newWarning = .tooMuchMovement
                } else {
                    // Simple drifting warning - keep QR in blue box
                    newWarning = .drifting
                }
                
                movementWarning = newWarning
                lastWarningTime = now
            } else {
                // Movement is acceptable - only clear warning after minimum display duration
                if let warningTime = lastWarningTime {
                    let elapsed = now.timeIntervalSince(warningTime)
                    if elapsed >= CameraManager.warningMinDisplayDuration {
                        movementWarning = nil
                        lastWarningTime = nil
                    }
                    // Otherwise keep showing the warning
                } else {
                    // No warning time recorded, clear immediately
                    movementWarning = nil
                }
            }
        }
        
        // During recording, only show drift warnings - distance warnings are for pre-recording only
        
        // Add to history
        recordingMovementHistory.append((timestamp: now, center: currentCenter))
        
        // Keep only last 2 seconds of history (at ~30fps = 60 frames)
        let cutoff = now.addingTimeInterval(-2.0)
        recordingMovementHistory.removeAll { $0.timestamp < cutoff }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Create Vision request for QR code detection
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self = self,
                  let results = request.results as? [VNBarcodeObservation] else { return }
            
            // Filter for QR codes only
            let qrCodes = results.filter { $0.symbology == .qr }
            
            Task { @MainActor in
                self.processQRCodes(qrCodes)
            }
        }
        
        // Detect QR codes specifically
        request.symbologies = [.qr]
        
        // Use .up orientation - Vision returns normalized coordinates (0-1)
        // The Y-flip is handled when converting to preview layer coordinates
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // Silently handle errors
        }
    }
    
    /// Calculates distance from camera to QR code in centimeters
    /// Uses known QR code size (6cm) and apparent pixel size
    /// Formula: distance = (real_size * focal_length) / pixel_size
    private func calculateDistanceToCm(corners: [CGPoint], imageSize: CGSize) -> Double {
        guard corners.count == 4 else { return 0 }
        
        // Convert normalized coordinates to pixels
        let pixelCorners = corners.map { corner in
            CGPoint(
                x: corner.x * imageSize.width,
                y: corner.y * imageSize.height
            )
        }
        
        // Calculate all edge lengths in pixels
        let edge1 = hypot(pixelCorners[0].x - pixelCorners[1].x, pixelCorners[0].y - pixelCorners[1].y)
        let edge2 = hypot(pixelCorners[1].x - pixelCorners[2].x, pixelCorners[1].y - pixelCorners[2].y)
        let edge3 = hypot(pixelCorners[2].x - pixelCorners[3].x, pixelCorners[2].y - pixelCorners[3].y)
        let edge4 = hypot(pixelCorners[3].x - pixelCorners[0].x, pixelCorners[3].y - pixelCorners[0].y)
        
        // Average edge length gives us a robust estimate
        let avgEdgeLengthPixels = (edge1 + edge2 + edge3 + edge4) / 4.0
        
        guard avgEdgeLengthPixels > 0 else { return 0 }
        
        // Distance formula: distance = (real_size * focal_length) / pixel_size
        // Result in cm because qrCodeSizeCm is in cm
        let distanceCm = (CameraManager.qrCodeSizeCm * CameraManager.focalLengthPixels) / Double(avgEdgeLengthPixels)
        
        return distanceCm
    }
    
    /// Processes detected QR codes and updates alignment state with temporal smoothing
    private func processQRCodes(_ observations: [VNBarcodeObservation]) {
        let now = Date()
        
        // During recording, track movement but don't update alignment UI
        if isRecording {
            processQRCodesDuringRecording(observations)
            return
        }
        
        // Extract QR code positions and corner points from current frame
        var positions: [CGRect] = []
        var allCorners: [[CGPoint]] = []
        
        // Image size for distance calculation (using capture session preset)
        let imageSize = CGSize(width: 1920, height: 1080)
        
        for observation in observations {
            // Use the bounding box for backward compatibility
            let box = observation.boundingBox
            positions.append(box)
            
            // Extract corner points for accurate visualization
            // VNBarcodeObservation provides corner points in normalized coordinates (0-1, bottom-left origin)
            let tl = observation.topLeft
            let tr = observation.topRight
            let br = observation.bottomRight
            let bl = observation.bottomLeft
            
            // Verify corner points are valid
            guard !tl.x.isNaN && !tl.y.isNaN,
                  !tr.x.isNaN && !tr.y.isNaN,
                  !br.x.isNaN && !br.y.isNaN,
                  !bl.x.isNaN && !bl.y.isNaN else {
                continue
            }
            
            // Convert to CGPoint array (in normalized coordinates, bottom-left origin)
            let rawCornerPoints = [
                CGPoint(x: CGFloat(tl.x), y: CGFloat(tl.y)),
                CGPoint(x: CGFloat(tr.x), y: CGFloat(tr.y)),
                CGPoint(x: CGFloat(br.x), y: CGFloat(br.y)),
                CGPoint(x: CGFloat(bl.x), y: CGFloat(bl.y))
            ]
            
            // Store corner points for visualization
            allCorners.append(rawCornerPoints)
        }
        
        let currentlyDetected = positions.count >= 2
        
        // Calculate current frame's distance and roll
        var currentDistance: CGFloat? = nil
        var currentRoll: CGFloat = 0
        
        if let firstCorners = allCorners.first, firstCorners.count == 4 {
            currentDistance = CGFloat(calculateDistanceToCm(corners: firstCorners, imageSize: imageSize))

            // Calculate roll from the longest horizontal edge of QR code
            // Vision provides: topLeft(0), topRight(1), bottomRight(2), bottomLeft(3)
            // Use the average of top and bottom edges to get a stable angle
            let topLeft = firstCorners[0]
            let topRight = firstCorners[1]
            let bottomRight = firstCorners[2]
            let bottomLeft = firstCorners[3]
            
            // Calculate angle of top edge
            let topDeltaX = topRight.x - topLeft.x
            let topDeltaY = topRight.y - topLeft.y
            let topAngle = atan2(topDeltaY, topDeltaX)
            
            // Calculate angle of bottom edge
            let bottomDeltaX = bottomRight.x - bottomLeft.x
            let bottomDeltaY = bottomRight.y - bottomLeft.y
            let bottomAngle = atan2(bottomDeltaY, bottomDeltaX)
            
            // Average the angles (handles slight perspective distortion)
            var avgAngle = (topAngle + bottomAngle) / 2.0
            
            // Convert to degrees
            var rollDegrees = avgAngle * 180.0 / .pi
            
            // Normalize to -90 to +90 range (we only care about small rotations from horizontal)
            // If angle is near ±180, it means the QR is nearly horizontal but detected "upside down"
            if rollDegrees > 90 {
                rollDegrees -= 180
            } else if rollDegrees < -90 {
                rollDegrees += 180
            }
            
            currentRoll = CGFloat(rollDegrees)
        }
        
        // Add current detection to history
        detectionHistory.append((
            timestamp: now,
            detected: currentlyDetected,
            corners: allCorners,
            distance: currentDistance,
            roll: currentRoll
        ))
        
        // Remove old entries outside the smoothing window
        let cutoff = now.addingTimeInterval(-CameraManager.smoothingWindowSeconds)
        detectionHistory.removeAll { $0.timestamp < cutoff }
        
        // Apply temporal smoothing: use majority vote from recent history
        let detectedCount = detectionHistory.filter { $0.detected }.count
        let totalCount = detectionHistory.count
        let detectionRatio = totalCount > 0 ? Double(detectedCount) / Double(totalCount) : 0
        
        let smoothedDetected = detectionRatio >= CameraManager.detectionThreshold
        
        // Use smoothed values - prefer recent detected frames for corners/distance/roll
        var smoothedCorners: [[CGPoint]] = allCorners
        var smoothedDistance: CGFloat? = currentDistance
        var smoothedRoll: CGFloat = currentRoll
        
        if smoothedDetected && !currentlyDetected {
            // We're smoothing over a gap - use the most recent detected frame's data
            if let lastDetected = detectionHistory.last(where: { $0.detected }) {
                smoothedCorners = lastDetected.corners
                smoothedDistance = lastDetected.distance
                smoothedRoll = lastDetected.roll
            }
        }
        
        // Build the alignment state
        var newState = AlignmentState()
        newState.qrCodePositions = positions
        newState.qrCodeCorners = smoothedCorners
        newState.bothQRCodesDetected = smoothedDetected
        newState.distanceToTopQR = smoothedDistance
        newState.qrCodeRoll = smoothedRoll
        
        // Calculate center of all QR codes for centering guidance
        if !smoothedCorners.isEmpty {
            var totalX: CGFloat = 0
            var totalY: CGFloat = 0
            var pointCount: CGFloat = 0
            
            for corners in smoothedCorners {
                for corner in corners {
                    totalX += corner.x
                    totalY += corner.y
                    pointCount += 1
                }
            }
            
            if pointCount > 0 {
                // Center in normalized coordinates (0-1)
                // Note: Vision uses bottom-left origin, so Y is already correct for our needs
                newState.qrCodesCenter = CGPoint(
                    x: totalX / pointCount,
                    y: totalY / pointCount
                )
            }
        }

        if smoothedDetected {
            // QR codes are reference markers only - no content validation needed
            newState.qrCodesMatchTemplate = true
            
            // Calculate distance between first two QR codes using smoothed corners
            if smoothedCorners.count >= 2 {
                // Calculate centers from corners
                let corners1 = smoothedCorners[0]
                let corners2 = smoothedCorners[1]
                
                let center1 = CGPoint(
                    x: corners1.reduce(0) { $0 + $1.x } / 4,
                    y: corners1.reduce(0) { $0 + $1.y } / 4
                )
                let center2 = CGPoint(
                    x: corners2.reduce(0) { $0 + $1.x } / 4,
                    y: corners2.reduce(0) { $0 + $1.y } / 4
                )
                
                // Convert normalized coordinates to approximate pixel distance
                // Account for the video aspect ratio (1920x1080)
                let pixelDistance = hypot(
                    (center2.x - center1.x) * 1920,
                    (center2.y - center1.y) * 1080
                )
                
                newState.measuredPixelDistance = pixelDistance
                newState.distanceFeedback = TemplateConfiguration.distanceFeedback(measuredDistance: pixelDistance)
                
                // Calculate angle from horizontal (in degrees)
                // Vision coordinates: origin at bottom-left, Y increases upward
                let deltaX = center2.x - center1.x
                let deltaY = center2.y - center1.y
                let angleRadians = atan2(deltaY, deltaX)
                let angleDegrees = angleRadians * 180 / .pi
                newState.angleFromHorizontal = angleDegrees
                
                // Validate orientation - very lenient for side-angle viewing
                newState.orientationValid = TemplateConfiguration.validateDiagonalAngle(angleDegrees, for: selectedHand)
            }
        }
        
        // Include viewing angle check from device motion
        newState.isViewingAngleGood = self.isViewingAngleGood
        
        self.alignmentState = newState
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Recording has started
    }
    
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            print("🎬 Recording finished at: \(outputFileURL.path)")
            self.isRecording = false
            
            // Capture the completion handler before clearing it
            let completion = self.recordingCompletion
            self.recordingCompletion = nil
            
            if let error = error {
                print("🎬 Recording error: \(error.localizedDescription)")
                completion?(nil, nil)
            } else {
                // Small delay to ensure file is fully written
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                
                // Verify the file exists and is readable
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: outputFileURL.path) {
                    // Check file size
                    if let attrs = try? fileManager.attributesOfItem(atPath: outputFileURL.path),
                       let size = attrs[.size] as? Int64 {
                        print("🎬 Video file size: \(size) bytes")
                    }
                    
                    let duration = self.recordingDuration
                    let metadata = SessionMetadata.create(hand: self.selectedHand, duration: duration)
                    
                    print("🎬 Calling completion handler")
                    completion?(outputFileURL, metadata)
                } else {
                    print("🎬 Recording file not found at: \(outputFileURL.path)")
                    completion?(nil, nil)
                }
            }
        }
    }
}

