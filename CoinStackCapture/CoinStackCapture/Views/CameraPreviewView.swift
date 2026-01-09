import SwiftUI
import AVFoundation

/// UIKit wrapper for AVCaptureVideoPreviewLayer
struct CameraPreviewView: UIViewRepresentable {
    
    /// The camera manager providing the capture session
    let cameraManager: CameraManager
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = cameraManager.captureSession
        view.previewLayer.videoGravity = .resizeAspectFill
        
        // Set up connection for front camera mirroring if needed
        DispatchQueue.main.async {
            if let connection = view.previewLayer.connection {
                // Handle mirroring for front camera
                if cameraManager.isUsingFrontCamera && connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Update session if changed
        if uiView.previewLayer.session !== cameraManager.captureSession {
            uiView.previewLayer.session = cameraManager.captureSession
        }
        
        // Handle mirroring updates for front camera
        if let connection = uiView.previewLayer.connection {
            if cameraManager.isUsingFrontCamera {
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
            } else {
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = true
                }
            }
        }
        
        // Update layer frame on bounds change
        uiView.setNeedsLayout()
    }
}

/// UIView subclass containing the preview layer
class CameraPreviewUIView: UIView {
    
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
}

/// Overlay showing QR code detection boxes and alignment guides
struct AlignmentOverlayView: View {
    
    /// Current alignment state
    let alignmentState: AlignmentState
    
    /// Size of the preview area
    let previewSize: CGSize
    
    /// Blue color for QR code highlight (distinct from green "ready" indicator)
    private let qrHighlightColor = Color(hex: "2196F3") // Material Blue
    
    // Video aspect ratio (1920x1080)
    private let videoAspectRatio: CGFloat = 1920.0 / 1080.0
    
    var body: some View {
        if #available(iOS 18.0, *) {
            ZStack {
                // QR code bounding boxes
                ForEach(alignmentState.qrCodePositions, id: \.self) { box in
                    let rect = transformedSquareRect(for: box, in: previewSize)
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(qrHighlightColor, lineWidth: 3)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(qrHighlightColor.opacity(0.15))
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                
                // Center guide lines
                if !alignmentState.isReadyToRecord {
                    // Vertical guide
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1, height: previewSize.height * 0.3)
                    
                    // Horizontal guide
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: previewSize.width * 0.3, height: 1)
                }
                
                // Corner brackets - green when ready, gray when not
                CornerBrackets(
                    color: alignmentState.isReadyToRecord ?
                    Color(hex: "4CAF50") :
                        Color(hex: "778DA9").opacity(0.5)
                )
                .padding(40)
            }
        } else {
            // Fallback on earlier versions
        }
    }
    
    /// Transforms a normalized Vision rect into a square rect in view coordinates,
    /// accounting for aspect-fill cropping and coordinate system differences.
    private func transformedSquareRect(for box: CGRect, in previewSize: CGSize) -> CGRect {
        let previewAspectRatio = previewSize.width / previewSize.height

        let scaleX: CGFloat
        let scaleY: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        if previewAspectRatio > videoAspectRatio {
            // Preview is wider - video is cropped top/bottom
            scaleX = previewSize.width
            scaleY = previewSize.width / videoAspectRatio
            offsetY = (scaleY - previewSize.height) / 2
            offsetX = 0
        } else {
            // Preview is taller - video is cropped left/right
            scaleY = previewSize.height
            scaleX = previewSize.height * videoAspectRatio
            offsetX = (scaleX - previewSize.width) / 2
            offsetY = 0
        }

        // Apply transformation - flip Y axis and apply scale
        let transformedX = box.minX * scaleX - offsetX
        let transformedY = (1 - box.maxY) * scaleY - offsetY
        let transformedWidth = box.width * scaleX
        let transformedHeight = box.height * scaleY

        // Make the box square by using the larger dimension and add 10% padding
        let size = max(transformedWidth, transformedHeight) * 1.1
        let centerX = transformedX + transformedWidth / 2
        let centerY = transformedY + transformedHeight / 2

        return CGRect(x: centerX - size / 2, y: centerY - size / 2, width: size, height: size)
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
                Rectangle()
                    .fill(color)
                    .frame(width: length, height: thickness)
                Rectangle()
                    .fill(color)
                    .frame(width: thickness, height: length - thickness)
                Spacer()
            }
            .frame(width: length, height: length)
            .position(x: length/2, y: length/2)
            
            // Top-right
            VStack(spacing: 0) {
                Rectangle()
                    .fill(color)
                    .frame(width: length, height: thickness)
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(color)
                        .frame(width: thickness, height: length - thickness)
                }
                Spacer()
            }
            .frame(width: length, height: length)
            .position(x: geo.size.width - length/2, y: length/2)
            
            // Bottom-left
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Rectangle()
                        .fill(color)
                        .frame(width: thickness, height: length - thickness)
                    Spacer()
                }
                Rectangle()
                    .fill(color)
                    .frame(width: length, height: thickness)
            }
            .frame(width: length, height: length)
            .position(x: length/2, y: geo.size.height - length/2)
            
            // Bottom-right
            VStack(spacing: 0) {
                Spacer()
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(color)
                        .frame(width: thickness, height: length - thickness)
                }
                Rectangle()
                    .fill(color)
                    .frame(width: length, height: thickness)
            }
            .frame(width: length, height: length)
            .position(x: geo.size.width - length/2, y: geo.size.height - length/2)
        }
    }
}

