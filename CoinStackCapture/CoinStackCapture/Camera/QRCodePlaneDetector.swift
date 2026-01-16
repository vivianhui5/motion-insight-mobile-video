import Foundation
import Vision
import CoreGraphics
import simd

/// Detects 3D plane orientation from QR code corner points
struct QRCodePlaneDetector {
    
    /// 3D plane information calculated from QR code corners
    struct PlaneInfo {
        /// Normal vector of the plane (in camera space)
        let normal: simd_float3
        
        /// Angle between plane normal and camera view direction (degrees)
        /// 0° = plane is parallel to camera (looking straight at it)
        /// 90° = plane is perpendicular to camera (edge-on view)
        let angleFromCamera: Float
        
        /// Tilt angle in X axis (roll, degrees)
        let tiltX: Float
        
        /// Tilt angle in Y axis (pitch, degrees)
        let tiltY: Float
        
        /// Whether the plane is reasonably flat (not too tilted)
        var isFlat: Bool {
            return abs(tiltX) < 30 && abs(tiltY) < 30
        }
    }
    
    /// Calculates 3D plane orientation from QR code corner points using perspective analysis
    /// - Parameter observation: Vision barcode observation with corner points
    /// - Returns: Plane information if calculation succeeds
    static func detectPlane(from observation: VNBarcodeObservation) -> PlaneInfo? {
        // Get corner points in normalized coordinates (0-1, bottom-left origin)
        // Note: These may not always be available, so we check validity
        let tl = observation.topLeft      // Top-left
        let tr = observation.topRight     // Top-right
        let br = observation.bottomRight  // Bottom-right
        let bl = observation.bottomLeft   // Bottom-left
        
        // Verify corner points are valid (not NaN or zero)
        guard !tl.x.isNaN && !tl.y.isNaN,
              !tr.x.isNaN && !tr.y.isNaN,
              !br.x.isNaN && !br.y.isNaN,
              !bl.x.isNaN && !bl.y.isNaN else {
            return nil
        }
        
        // Convert to CGPoints for easier math
        let corners = [
            CGPoint(x: tl.x, y: tl.y),  // top-left
            CGPoint(x: tr.x, y: tr.y),  // top-right
            CGPoint(x: br.x, y: br.y),  // bottom-right
            CGPoint(x: bl.x, y: bl.y)   // bottom-left
        ]
        
        // Calculate side lengths to detect perspective distortion
        let topWidth = distance(corners[0], corners[1])      // top edge
        let bottomWidth = distance(corners[3], corners[2])   // bottom edge
        let leftHeight = distance(corners[0], corners[3])   // left edge
        let rightHeight = distance(corners[1], corners[2])  // right edge
        
        // If QR code is perfectly flat and parallel to camera:
        // - All sides should be equal
        // - Opposite sides should be parallel
        
        // Calculate perspective distortion ratios
        let widthRatio = topWidth / bottomWidth  // >1 means top is farther (tilted away)
        let heightRatio = leftHeight / rightHeight  // >1 means left is farther
        
        // Estimate plane normal from perspective distortion
        // If top is wider than bottom, plane is tilted away at top (positive Y tilt)
        // If left is taller than right, plane is tilted away at left (positive X tilt)
        
        // Convert ratios to angles (simplified model)
        // Assuming a square QR code, the ratio tells us the tilt
        // Clamp ratios to avoid extreme values
        let clampedWidthRatio = max(0.5, min(2.0, widthRatio))
        let clampedHeightRatio = max(0.5, min(2.0, heightRatio))
        
        let tiltY = atan((clampedWidthRatio - 1.0) * 2.0) * 180.0 / .pi  // Pitch (Y rotation)
        let tiltX = atan((clampedHeightRatio - 1.0) * 2.0) * 180.0 / .pi  // Roll (X rotation)
        
        // Calculate plane normal vector from tilt angles
        // Normal points "up" from the plane surface
        let tiltYRad = Float(tiltY) * .pi / 180.0
        let tiltXRad = Float(tiltX) * .pi / 180.0
        
        // Normal vector in camera space (Z points into camera)
        // Rotations: Y tilt rotates around Y axis, X tilt around X axis
        let normal = simd_float3(
            sin(tiltXRad),           // X component from roll
            sin(tiltYRad),           // Y component from pitch
            cos(tiltXRad) * cos(tiltYRad)  // Z component (depth)
        )
        let normalized = simd_normalize(normal)
        
        // Camera looks down -Z axis, so direction is (0, 0, -1)
        let cameraDirection = simd_float3(0, 0, -1)
        
        // Angle between plane normal and camera direction
        let dotProduct = simd_dot(normalized, cameraDirection)
        let angleRadians = acos(max(-1, min(1, dotProduct)))
        let angleDegrees = angleRadians * 180.0 / .pi
        
        return PlaneInfo(
            normal: normalized,
            angleFromCamera: angleDegrees,
            tiltX: Float(tiltX),
            tiltY: Float(tiltY)
        )
    }
    
    /// Calculates distance between two points
    private static func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }
    
    /// Calculates average plane info from multiple QR codes
    static func averagePlaneInfo(from observations: [VNBarcodeObservation]) -> PlaneInfo? {
        let planeInfos = observations.compactMap { detectPlane(from: $0) }
        guard !planeInfos.isEmpty else { return nil }
        
        // Average the normal vectors
        let avgNormal = simd_normalize(
            planeInfos.map { $0.normal }.reduce(simd_float3(0, 0, 0), +) / Float(planeInfos.count)
        )
        
        let avgAngle = planeInfos.map { $0.angleFromCamera }.reduce(0, +) / Float(planeInfos.count)
        let avgTiltX = planeInfos.map { $0.tiltX }.reduce(0, +) / Float(planeInfos.count)
        let avgTiltY = planeInfos.map { $0.tiltY }.reduce(0, +) / Float(planeInfos.count)
        
        return PlaneInfo(
            normal: avgNormal,
            angleFromCamera: avgAngle,
            tiltX: avgTiltX,
            tiltY: avgTiltY
        )
    }
}
