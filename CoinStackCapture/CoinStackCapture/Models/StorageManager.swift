import Foundation
import Photos
import UIKit

/// Manages video and metadata storage for the app
class StorageManager {
    
    /// Shared instance
    static let shared = StorageManager()
    
    private init() {}
    
    /// Directory for storing videos
    private var videosDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videosPath = documentsPath.appendingPathComponent("CoinStackVideos", isDirectory: true)
        
        // Create directory if needed
        if !FileManager.default.fileExists(atPath: videosPath.path) {
            try? FileManager.default.createDirectory(at: videosPath, withIntermediateDirectories: true)
        }
        
        return videosPath
    }
    
    /// Saves a video and its metadata to app storage
    /// - Parameters:
    ///   - sourceURL: Temporary URL of the recorded video
    ///   - metadata: Session metadata to save alongside the video
    /// - Returns: Tuple of (video URL, metadata URL) in app storage
    func saveVideo(from sourceURL: URL, with metadata: SessionMetadata) throws -> (videoURL: URL, metadataURL: URL) {
        let filename = metadata.generateVideoFilename()
        let videoDestination = videosDirectory.appendingPathComponent(filename)
        let metadataFilename = filename.replacingOccurrences(of: ".mp4", with: ".json")
        let metadataDestination = videosDirectory.appendingPathComponent(metadataFilename)
        
        // Copy video file
        if FileManager.default.fileExists(atPath: videoDestination.path) {
            try FileManager.default.removeItem(at: videoDestination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: videoDestination)
        
        // Save metadata
        if let jsonData = metadata.toJSONData() {
            try jsonData.write(to: metadataDestination)
        }
        
        return (videoDestination, metadataDestination)
    }
    
    /// Saves video to the Photos library
    /// - Parameter videoURL: URL of the video to save
    /// - Returns: Success status
    @MainActor
    func saveToPhotosLibrary(videoURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        
        guard status == .authorized || status == .limited else {
            throw StorageError.photoLibraryAccessDenied
        }
        
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        }
    }
    
    /// Lists all saved recordings
    func listSavedRecordings() -> [(video: URL, metadata: URL?)] {
        var recordings: [(video: URL, metadata: URL?)] = []
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: videosDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return recordings
        }
        
        let videoFiles = contents.filter { $0.pathExtension == "mp4" }
        
        for videoURL in videoFiles {
            let metadataURL = videoURL.deletingPathExtension().appendingPathExtension("json")
            let hasMetadata = FileManager.default.fileExists(atPath: metadataURL.path)
            recordings.append((videoURL, hasMetadata ? metadataURL : nil))
        }
        
        return recordings
    }
    
    /// Deletes a recording and its metadata
    func deleteRecording(videoURL: URL) throws {
        try FileManager.default.removeItem(at: videoURL)
        
        let metadataURL = videoURL.deletingPathExtension().appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            try FileManager.default.removeItem(at: metadataURL)
        }
    }
}

/// Storage-related errors
enum StorageError: LocalizedError {
    case photoLibraryAccessDenied
    case saveFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .photoLibraryAccessDenied:
            return "Photo library access was denied. Please enable it in Settings."
        case .saveFailed(let reason):
            return "Failed to save: \(reason)"
        }
    }
}

