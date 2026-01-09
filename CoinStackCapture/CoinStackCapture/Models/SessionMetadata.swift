import Foundation
import UIKit

/// Represents which hand is being used for the coin stacking task
enum HandSelection: String, Codable, Hashable {
    case left = "left"
    case right = "right"
    
    /// Returns the corresponding template filename
    var templateFilename: String {
        switch self {
        case .left:
            return "left-template"
        case .right:
            return "right-template"
        }
    }
}

/// Metadata attached to each recording for ML pipeline ingestion
struct SessionMetadata: Codable {
    /// Which hand was used for the task
    let handUsed: HandSelection
    
    /// Template filename used for validation
    let templateFilename: String
    
    /// Recording start timestamp in ISO 8601 format
    let timestamp: String
    
    /// Duration of the recording in seconds
    let recordingDurationSeconds: Double
    
    /// Device model identifier (e.g., "iPhone14,5")
    let deviceModel: String
    
    /// App version string
    let appVersion: String
    
    /// iOS version
    let osVersion: String
    
    /// Video resolution
    let videoResolution: String
    
    /// Frame rate
    let frameRate: Int
    
    /// Creates metadata for the current session
    static func create(
        hand: HandSelection,
        duration: Double
    ) -> SessionMetadata {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var systemInfo = utsname()
        uname(&systemInfo)
        let deviceModel = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
        
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let osVersion = UIDevice.current.systemVersion
        
        return SessionMetadata(
            handUsed: hand,
            templateFilename: hand.templateFilename,
            timestamp: dateFormatter.string(from: Date()),
            recordingDurationSeconds: duration,
            deviceModel: deviceModel,
            appVersion: appVersion,
            osVersion: osVersion,
            videoResolution: "1920x1080",
            frameRate: 30
        )
    }
    
    /// Generates the filename for the video
    func generateVideoFilename() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestampStr = dateFormatter.string(from: Date())
        return "coinstack_\(timestampStr)_\(handUsed.rawValue).mp4"
    }
    
    /// Converts metadata to JSON data
    func toJSONData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(self)
    }
}

