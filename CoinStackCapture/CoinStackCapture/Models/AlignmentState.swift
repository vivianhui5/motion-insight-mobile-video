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
    
    /// Detected QR code positions (bounding boxes for backward compatibility)
    var qrCodePositions: [CGRect] = []
    
    /// Detected QR code corner points (for accurate quadrilateral visualization)
    /// Each array contains 4 points: [topLeft, topRight, bottomRight, bottomLeft] in normalized coordinates
    var qrCodeCorners: [[CGPoint]] = []
    
    /// Measured pixel distance between QR codes
    var measuredPixelDistance: CGFloat = 0
    
    /// Calculated angle of the line between QR codes (degrees from horizontal)
    /// Left template: expects ~45° (top-left to bottom-right diagonal)
    /// Right template: expects ~-45° (bottom-left to top-right diagonal)
    var angleFromHorizontal: CGFloat = 0
    
    /// Whether the phone's viewing angle is good (not too flat/bird's eye)
    var isViewingAngleGood: Bool = true
    
    /// Estimated distance from camera to the top QR code (in centimeters)
    /// Calculated using known QR code size (6cm) and apparent pixel size
    var distanceToTopQR: CGFloat?
    
    /// QR code roll angle (degrees) - how much the QR code's top edge is rotated from horizontal
    /// 0° = top edge is perfectly horizontal (parallel to screen bottom)
    /// Positive = clockwise rotation, Negative = counter-clockwise
    var qrCodeRoll: CGFloat = 0
    
    /// Center position of all detected QR codes (normalized 0-1, where 0.5 is center)
    /// Used for centering guidance
    var qrCodesCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)
    
    /// Roll tolerance in degrees - within this range is considered "good"
    static let rollTolerance: CGFloat = 5.0
    
    /// Horizontal center tolerance - stricter, QR codes should be well-centered horizontally
    /// 0.08 means within 8% of center (0.42-0.58 range)
    static let horizontalCenterTolerance: CGFloat = 0.08
    
    /// Vertical center tolerance - more lenient for vertical positioning
    static let verticalCenterTolerance: CGFloat = 0.15
    
    /// Ideal vertical position for QR codes - bottom 2/3 of screen
    /// In Vision coordinates: y=0 is bottom, y=1 is top
    /// We want QR codes in bottom 2/3, so ideal center is around 0.33
    static let idealVerticalCenter: CGFloat = 0.33
    
    /// Whether the roll is within acceptable tolerance (±5°)
    var isRollGood: Bool {
        return abs(qrCodeRoll) <= AlignmentState.rollTolerance
    }
    
    /// Whether QR codes are horizontally centered (strict - within 8% of center)
    var isHorizontallyCentered: Bool {
        return abs(qrCodesCenter.x - 0.5) <= AlignmentState.horizontalCenterTolerance
    }
    
    /// Whether QR codes are in the bottom 2/3 of screen (within tolerance)
    /// Target is y=0.33 (middle of bottom 2/3)
    var isVerticallyCentered: Bool {
        return abs(qrCodesCenter.y - AlignmentState.idealVerticalCenter) <= AlignmentState.verticalCenterTolerance
    }
    
    /// Whether QR codes are well-centered overall
    var isCentered: Bool {
        return isHorizontallyCentered && isVerticallyCentered
    }
    
    /// Returns true if all alignment conditions are met
    /// Orientation is very lenient - focus is on distance
    var isReadyToRecord: Bool {
        return bothQRCodesDetected &&
               qrCodesMatchTemplate &&
               distanceFeedback == .optimal &&
               orientationValid &&
               isViewingAngleGood
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
            if !isViewingAngleGood {
                return "Angle your phone properly"
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
        
        // Show angle hint if viewing angle is too flat
        if !isViewingAngleGood {
            return "Don't point straight down at the paper"
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
        } else if !orientationValid {
            return "rotate.right"
        } else if !isViewingAngleGood {
            return "iphone.gen3.radiowaves.left.and.right"
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

