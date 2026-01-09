import Foundation
import Vision
import CoreGraphics

/// Validates QR code positions for distance and orientation reference.
/// QR codes serve as reference markers only - their content is not validated.
class QRCodeValidator {
    
    /// Result of QR code validation
    struct ValidationResult {
        /// Whether at least two QR codes were found
        let bothCodesFound: Bool
        
        /// Bounding boxes of detected QR codes (normalized coordinates)
        let boundingBoxes: [CGRect]
        
        /// Calculated pixel distance between QR code centers
        let pixelDistance: CGFloat?
        
        /// Angle of line between QR codes from horizontal (degrees)
        let angleFromHorizontal: CGFloat?
        
        /// Distance feedback (too close, too far, or optimal)
        let distanceFeedback: DistanceFeedback?
        
        /// Whether orientation is valid
        let orientationValid: Bool
        
        /// Overall validation passed
        var isValid: Bool {
            return bothCodesFound &&
                   distanceFeedback == .optimal &&
                   orientationValid
        }
    }
    
    /// Validates QR codes from Vision observations
    /// - Parameters:
    ///   - observations: Barcode observations from Vision
    ///   - expectedHand: The hand selection determining expected diagonal orientation
    ///   - imageWidth: Width of the source image in pixels
    ///   - imageHeight: Height of the source image in pixels
    /// - Returns: Validation result
    func validate(
        observations: [VNBarcodeObservation],
        expectedHand: HandSelection,
        imageWidth: CGFloat = 1920,
        imageHeight: CGFloat = 1080
    ) -> ValidationResult {
        
        // Filter for QR codes
        let qrCodes = observations.filter { $0.symbology == .qr }
        let boxes = qrCodes.map { $0.boundingBox }
        
        // Check if at least two QR codes found
        let bothFound = boxes.count >= 2
        
        // Calculate distance and orientation if we have two codes
        var pixelDistance: CGFloat? = nil
        var angle: CGFloat? = nil
        var distFeedback: DistanceFeedback? = nil
        var orientValid = false
        
        if boxes.count >= 2 {
            // Calculate centers in pixel coordinates
            let center1 = CGPoint(
                x: boxes[0].midX * imageWidth,
                y: boxes[0].midY * imageHeight
            )
            let center2 = CGPoint(
                x: boxes[1].midX * imageWidth,
                y: boxes[1].midY * imageHeight
            )
            
            // Euclidean distance between QR code centers
            let dist = hypot(center2.x - center1.x, center2.y - center1.y)
            pixelDistance = dist
            distFeedback = TemplateConfiguration.distanceFeedback(measuredDistance: dist)
            
            // Angle from horizontal (in degrees)
            let deltaX = center2.x - center1.x
            let deltaY = center2.y - center1.y
            let angleRad = atan2(deltaY, deltaX)
            let angleDegrees = angleRad * 180 / .pi
            angle = angleDegrees
            
            // Validate diagonal angle based on expected template layout
            orientValid = TemplateConfiguration.validateDiagonalAngle(angleDegrees, for: expectedHand)
        }
        
        return ValidationResult(
            bothCodesFound: bothFound,
            boundingBoxes: boxes,
            pixelDistance: pixelDistance,
            angleFromHorizontal: angle,
            distanceFeedback: distFeedback,
            orientationValid: orientValid
        )
    }
}

