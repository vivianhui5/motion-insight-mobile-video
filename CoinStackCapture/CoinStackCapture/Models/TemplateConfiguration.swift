import Foundation
import CoreGraphics

/// Configuration constants for template validation.
/// QR codes serve as reference markers for distance and positioning only.
struct TemplateConfiguration {
    
    // MARK: - QR Code Specifications
    // QR Pattern: 6.0cm (black area), Version 2, Error Correction: H (High)
    // Icon size: 24.6mm
    // Paper: Standard printer paper (Letter 8.5"×11" or A4)
    
    /// QR code size in centimeters
    static let qrCodeSizeCm: CGFloat = 6.0
    
    /// QR code version
    static let qrCodeVersion: Int = 2
    
    /// Icon size in millimeters
    static let iconSizeMm: CGFloat = 24.6
    
    // MARK: - Physical Measurements
    
    /// Physical distance between QR code centers in centimeters
    /// Diagonal distance: 22.5cm
    static let physicalQRDistanceCm: CGFloat = 22.5
    
    /// Expected pixel distance at optimal recording distance
    /// Calibrated for 1080p resolution at ~35-40cm from camera
    /// At this distance, 22.5cm physical ≈ 500 pixels diagonal
    static let expectedPixelDistanceAtOptimalDistance: CGFloat = 500.0
    
    /// Tolerance percentage for distance validation (±25% for flexibility)
    static let distanceTolerancePercent: CGFloat = 0.25
    
    /// Minimum acceptable pixel distance between QR codes
    static var minimumPixelDistance: CGFloat {
        expectedPixelDistanceAtOptimalDistance * (1 - distanceTolerancePercent)
    }
    
    /// Maximum acceptable pixel distance between QR codes
    static var maximumPixelDistance: CGFloat {
        expectedPixelDistanceAtOptimalDistance * (1 + distanceTolerancePercent)
    }
    
    // MARK: - QR Code Positions
    // Left template: QR codes on top-left and bottom-right corners
    // Right template: QR codes on bottom-left and top-right corners
    
    /// Expected diagonal angle for left template (degrees from horizontal)
    /// Top-left to bottom-right = approximately -45° (going down-right)
    static let leftTemplateDiagonalAngle: CGFloat = -45.0
    
    /// Expected diagonal angle for right template (degrees from horizontal)
    /// Bottom-left to top-right = approximately +45° (going up-right)
    static let rightTemplateDiagonalAngle: CGFloat = 45.0
    
    /// Maximum allowed angle deviation from expected diagonal (degrees)
    /// Moderately lenient to allow side-angle viewing, but indicator only turns green
    /// when alignment is reasonably good
    static let maxAngleDeviationDegrees: CGFloat = 40.0
    
    // MARK: - Helper Methods
    
    /// Returns expected diagonal angle for a hand selection
    static func expectedDiagonalAngle(for hand: HandSelection) -> CGFloat {
        switch hand {
        case .left:
            return leftTemplateDiagonalAngle
        case .right:
            return rightTemplateDiagonalAngle
        }
    }
    
    /// Validates the diagonal angle between detected QR codes
    /// Accepts angles in either direction (QR1→QR2 or QR2→QR1)
    static func validateDiagonalAngle(_ measuredAngle: CGFloat, for hand: HandSelection) -> Bool {
        let deviation = angleDeviation(measuredAngle, for: hand)
        return deviation < maxAngleDeviationDegrees
    }
    
    /// Calculates the minimum angle deviation from expected (handles 180° flip)
    private static func angleDeviation(_ measuredAngle: CGFloat, for hand: HandSelection) -> CGFloat {
        let expectedAngle = expectedDiagonalAngle(for: hand)
        
        // Check if angle matches expected or opposite direction (180° flip)
        let deviation1 = abs(measuredAngle - expectedAngle)
        let deviation2 = abs(measuredAngle - (expectedAngle + 180))
        let deviation3 = abs(measuredAngle - (expectedAngle - 180))
        
        return min(deviation1, min(deviation2, deviation3))
    }
    
    /// Calculates the distance feedback based on measured pixel distance
    static func distanceFeedback(measuredDistance: CGFloat) -> DistanceFeedback {
        if measuredDistance < minimumPixelDistance {
            return .tooFar
        } else if measuredDistance > maximumPixelDistance {
            return .tooClose
        } else {
            return .optimal
        }
    }
}

/// Feedback about camera distance from template
enum DistanceFeedback {
    case tooClose
    case tooFar
    case optimal
    
    var message: String {
        switch self {
        case .tooClose:
            return "Move farther from the paper"
        case .tooFar:
            return "Move closer to the paper"
        case .optimal:
            return "Distance is good"
        }
    }
}

