import Foundation
import CoreGraphics

/// Represents the current alignment state of the camera with the template
struct AlignmentState {
    /// Whether both QR codes are currently detected
    var bothQRCodesDetected: Bool = false
    
    /// Whether detected QR codes match the expected template
    var qrCodesMatchTemplate: Bool = false
    
    /// Current distance feedback
    var distanceFeedback: DistanceFeedback = .tooFar
    
    /// Whether the paper orientation is acceptable (very lenient)
    var orientationValid: Bool = false
    
    /// Detected QR code positions (for visualization)
    var qrCodePositions: [CGRect] = []
    
    /// Measured pixel distance between QR codes
    var measuredPixelDistance: CGFloat = 0
    
    /// Calculated angle of the line between QR codes (degrees from horizontal)
    /// Left template: expects ~45° (top-left to bottom-right diagonal)
    /// Right template: expects ~-45° (bottom-left to top-right diagonal)
    var angleFromHorizontal: CGFloat = 0
    
    /// Returns true if all alignment conditions are met
    /// Orientation is very lenient - focus is on distance
    var isReadyToRecord: Bool {
        return bothQRCodesDetected &&
               qrCodesMatchTemplate &&
               distanceFeedback == .optimal &&
               orientationValid
    }
    
    /// Human-readable feedback message - prioritizes distance over orientation
    var feedbackMessage: String {
        if !bothQRCodesDetected {
            return "Position both QR codes in frame"
        }
        
        // Prioritize distance feedback over orientation
        switch distanceFeedback {
        case .tooClose:
            return "Move farther away"
        case .tooFar:
            return "Move closer"
        case .optimal:
            if !orientationValid {
                return "Paper is too tilted"
            }
            return "Perfect — Ready to record"
        }
    }
    
    /// Secondary hint message for additional guidance
    var feedbackHint: String? {
        // No hints when ready to record - everything is good!
        if isReadyToRecord {
            return nil
        }
        
        if !bothQRCodesDetected {
            return "Both corner QR codes should be visible"
        }
        
        // Show distance hint first (most important)
        if distanceFeedback != .optimal {
            return "Adjust distance until indicator is green"
        }
        
        // Only show orientation hint if distance is good but orientation is invalid
        if !orientationValid {
            return "Adjust paper angle"
        }
        
        return nil
    }
    
    /// Icon name for the current state
    var feedbackIcon: String {
        if isReadyToRecord {
            return "checkmark.circle.fill"
        } else if !bothQRCodesDetected {
            return "viewfinder"
        } else if distanceFeedback != .optimal {
            return "arrow.up.and.down"
        } else {
            return "rotate.right"
        }
    }
    
    /// Color name for the current state
    var feedbackColorName: String {
        if isReadyToRecord {
            return "AlignmentGood"
        } else {
            return "AlignmentWarning"
        }
    }
}

