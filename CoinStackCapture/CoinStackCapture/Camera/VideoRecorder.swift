import AVFoundation
import Foundation

/// Helper class for video recording operations
class VideoRecorder {
    
    /// Output URL for the video file
    let outputURL: URL
    
    /// Whether recording is currently active
    private(set) var isRecording = false
    
    /// Recording start time
    private var startTime: Date?
    
    /// Creates a new video recorder
    /// - Parameter outputURL: Where to save the video file
    init(outputURL: URL) {
        self.outputURL = outputURL
    }
    
    /// Duration of the current or last recording
    var recordingDuration: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    /// Called when recording starts
    func didStartRecording() {
        isRecording = true
        startTime = Date()
    }
    
    /// Called when recording finishes
    func didFinishRecording() {
        isRecording = false
    }
}

/// Errors related to video recording
enum VideoRecordingError: LocalizedError {
    case setupFailed
    case recordingInterrupted
    case encodingFailed
    case storageFull
    
    var errorDescription: String? {
        switch self {
        case .setupFailed:
            return "Failed to set up video recording"
        case .recordingInterrupted:
            return "Recording was interrupted"
        case .encodingFailed:
            return "Failed to encode video"
        case .storageFull:
            return "Not enough storage space"
        }
    }
}
