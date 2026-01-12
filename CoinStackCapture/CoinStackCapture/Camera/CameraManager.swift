@preconcurrency import AVFoundation
import UIKit
import Vision
import CoreMotion

/// Manages camera session, preview, and frame processing for QR code detection
@MainActor
class CameraManager: NSObject, ObservableObject {
    
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
    
    /// Current device tilt angle (degrees from horizontal)
    @Published var deviceTiltAngle: Double = 0
    
    /// Current device pitch angle (how much it's tilted forward/looking down)
    /// 0 = looking straight ahead, -90 = looking straight down (bird's eye)
    @Published var devicePitchAngle: Double = 0
    
    /// Whether the viewing angle is good (not too flat/bird's eye view)
    /// Phone should be angled to look at paper from the side, not directly above
    @Published var isViewingAngleGood = true
    
    /// Whether using front camera
    @Published var isUsingFrontCamera = false
    
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
            
            // Calculate pitch angle (how much the phone is looking down)
            // gravity.z: -1 = looking straight down (bird's eye), 0 = looking straight ahead
            // Convert to degrees: 0 = straight ahead, -90 = straight down
            let pitchAngle = asin(-gravity.z) * 180 / .pi
            self.devicePitchAngle = pitchAngle
            
            // Good viewing angle: phone should be tilted 10-60° down (not flat/bird's eye)
            // At 100cm horizontal, 50cm vertical = arctan(0.5) ≈ 27° is ideal
            // Allow range of 10° to 60° to be flexible
            let isTooFlat = pitchAngle > 60  // Looking too straight down (bird's eye)
            let isTooStraight = pitchAngle < 5  // Looking almost straight ahead
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
    
    /// Processes detected QR codes and updates alignment state
    private func processQRCodes(_ observations: [VNBarcodeObservation]) {
        // Don't update alignment during recording
        guard !isRecording else { return }
        
        var newState = AlignmentState()
        
        // Extract QR code positions - use the corner points for accurate square bounds
        var positions: [CGRect] = []
        
        for observation in observations {
            // Use the bounding box directly - Vision provides it in normalized coordinates
            // The bounding box from Vision is the axis-aligned bounding box of the QR code
            let box = observation.boundingBox
            positions.append(box)
        }
        
        newState.qrCodePositions = positions
        newState.bothQRCodesDetected = positions.count >= 2
        
        if newState.bothQRCodesDetected {
            // QR codes are reference markers only - no content validation needed
            newState.qrCodesMatchTemplate = true
            
            // Calculate distance between first two QR codes
            if positions.count >= 2 {
                let center1 = CGPoint(x: positions[0].midX, y: positions[0].midY)
                let center2 = CGPoint(x: positions[1].midX, y: positions[1].midY)
                
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
