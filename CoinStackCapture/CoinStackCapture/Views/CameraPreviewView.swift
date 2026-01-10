import SwiftUI
import AVFoundation

/// UIKit wrapper for AVCaptureVideoPreviewLayer with QR code highlighting
struct CameraPreviewView: UIViewRepresentable {
    
    /// The camera manager providing the capture session
    @ObservedObject var cameraManager: CameraManager
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        // Connect session immediately on view creation
        view.previewLayer.session = cameraManager.captureSession
        view.previewLayer.videoGravity = .resizeAspectFill
        print("📺 Preview layer created and connected to session")
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Ensure session stays connected (reconnect if needed)
        let session = cameraManager.captureSession
        
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
            print("📺 Preview layer reconnected to session")
        }
        
        uiView.previewLayer.videoGravity = .resizeAspectFill
        
        // Update QR code boxes using Vision coordinates
        // The preview layer handles all coordinate conversion automatically
        uiView.updateQRCodeBoxes(cameraManager.alignmentState.qrCodePositions)
        
        // Force layout update when camera becomes ready or session is running
        if cameraManager.isCameraReady || cameraManager.isSessionRunning {
            uiView.setNeedsLayout()
            uiView.layoutIfNeeded()
        }
    }
}

/// UIView subclass containing the preview layer and QR code overlay
class CameraPreviewUIView: UIView {
    
    /// Shape layers for QR code highlighting
    private var qrBoxLayers: [CAShapeLayer] = []
    
    /// Color for QR code highlight
    private let highlightColor = UIColor(red: 0.13, green: 0.59, blue: 0.95, alpha: 1.0) // #2196F3
    
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
    
    /// Updates QR code highlight boxes using Vision bounding boxes
    /// Vision provides normalized coordinates (0-1) with origin at bottom-left
    func updateQRCodeBoxes(_ boxes: [CGRect]) {
        // Remove old layers
        for layer in qrBoxLayers {
            layer.removeFromSuperlayer()
        }
        qrBoxLayers.removeAll()
        
        // Create new layers for each detected QR code
        for box in boxes {
            // Vision coordinates: origin at bottom-left, Y increases upward
            // Metadata output rect: origin at top-left, Y increases downward
            // Flip Y coordinate to convert
            let flippedBox = CGRect(
                x: box.origin.x,
                y: 1 - box.origin.y - box.height,
                width: box.width,
                height: box.height
            )
            
            // Use the preview layer's built-in coordinate conversion
            // This handles all aspect ratio and orientation transformations automatically
            let convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: flippedBox)
            
            // Create shape layer for the box
            let shapeLayer = CAShapeLayer()
            let path = UIBezierPath(roundedRect: convertedRect, cornerRadius: 4)
            shapeLayer.path = path.cgPath
            shapeLayer.strokeColor = highlightColor.cgColor
            shapeLayer.fillColor = highlightColor.withAlphaComponent(0.1).cgColor
            shapeLayer.lineWidth = 2
            
            layer.addSublayer(shapeLayer)
            qrBoxLayers.append(shapeLayer)
        }
    }
}

/// Overlay showing alignment guides (QR boxes are drawn in UIKit layer)
struct AlignmentOverlayView: View {
    
    let alignmentState: AlignmentState
    let previewSize: CGSize
    
    var body: some View {
        ZStack {
            // Center guide lines
            if !alignmentState.isReadyToRecord {
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1, height: previewSize.height * 0.3)
                
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: previewSize.width * 0.3, height: 1)
            }
            
            // Corner brackets
            CornerBrackets(
                color: alignmentState.isReadyToRecord ?
                    Color(hex: "4CAF50") :
                    Color(hex: "778DA9").opacity(0.5)
            )
            .padding(40)
        }
    }
}

/// Corner bracket decorations for the camera frame
private struct CornerBrackets: View {
    let color: Color
    let length: CGFloat = 30
    let thickness: CGFloat = 3
    
    var body: some View {
        GeometryReader { geo in
            // Top-left
            VStack(spacing: 0) {
                Rectangle().fill(color).frame(width: length, height: thickness)
                Rectangle().fill(color).frame(width: thickness, height: length - thickness)
                Spacer()
            }
            .frame(width: length, height: length)
            .position(x: length/2, y: length/2)
            
            // Top-right
            VStack(spacing: 0) {
                Rectangle().fill(color).frame(width: length, height: thickness)
                HStack {
                    Spacer()
                    Rectangle().fill(color).frame(width: thickness, height: length - thickness)
                }
                Spacer()
            }
            .frame(width: length, height: length)
            .position(x: geo.size.width - length/2, y: length/2)
            
            // Bottom-left
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Rectangle().fill(color).frame(width: thickness, height: length - thickness)
                    Spacer()
                }
                Rectangle().fill(color).frame(width: length, height: thickness)
            }
            .frame(width: length, height: length)
            .position(x: length/2, y: geo.size.height - length/2)
            
            // Bottom-right
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    Rectangle().fill(color).frame(width: thickness, height: length - thickness)
                }
                Rectangle().fill(color).frame(width: length, height: thickness)
            }
            .frame(width: length, height: length)
            .position(x: geo.size.width - length/2, y: geo.size.height - length/2)
        }
    }
}
