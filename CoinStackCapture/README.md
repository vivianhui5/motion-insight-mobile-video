# Coin Stack Capture

An iOS app for standardized video data collection of patients performing a coin stacking task for medical screening and clinical review.

## Requirements

- iOS 16.0+
- iPhone with rear camera
- Xcode 15.0+

## Features

- **QR Code Validation**: Real-time detection and validation of template QR codes
- **Alignment Guidance**: Visual feedback for camera distance and paper orientation
- **1080p Recording**: High-quality video capture at 30fps
- **Metadata Export**: JSON metadata files for ML pipeline ingestion
- **Photos Export**: Optional saving to device photo library

## Project Structure

```
CoinStackCapture/
├── CoinStackCaptureApp.swift    # App entry point
├── ContentView.swift            # Root navigation
├── Views/
│   ├── LandingView.swift        # Welcome screen
│   ├── HandSelectionView.swift  # Left/right hand selection
│   ├── CameraAlignmentView.swift # Camera + recording screen
│   ├── CameraPreviewView.swift  # AVFoundation camera preview
│   ├── VideoReviewView.swift    # Playback review
│   ├── VideoPlayerView.swift    # Video player component
│   └── SaveFinishView.swift     # Save confirmation
├── Camera/
│   ├── CameraManager.swift      # Camera session management
│   ├── QRCodeValidator.swift    # QR code validation logic
│   └── VideoRecorder.swift      # Recording utilities
├── Models/
│   ├── SessionMetadata.swift    # Recording metadata model
│   ├── TemplateConfiguration.swift # Template constants
│   ├── AlignmentState.swift     # Alignment state model
│   └── StorageManager.swift     # File storage management
├── Resources/
│   ├── left-template.pdf        # Left hand template
│   └── right-template.pdf       # Right hand template
└── Assets.xcassets/             # App assets
```

## App Flow

1. **Landing Screen**: Introduction and task explanation
2. **Hand Selection**: Choose left or right hand template
3. **Camera Alignment**: Position template with QR code validation
4. **Recording**: Capture video when alignment is valid
5. **Review**: Playback recorded video
6. **Save**: Store video and metadata

## Template Requirements

### Paper & Printing
- **Paper Size**: Standard printer paper (Letter 8.5"×11" or A4)
- **Orientation**: Landscape

### QR Code Specifications
- **QR Size**: 6.0cm × 6.0cm (black area)
- **QR Version**: V2
- **Error Correction**: H (High)
- **Icon Size**: 24.6mm (center logo)
- **Content**: Any (QR codes are reference markers only)

### QR Code Placement
- **Distance**: 22.5cm between QR code centers (diagonal)

**Left Hand Template:**
- QR code 1: Top-left corner
- QR code 2: Bottom-right corner

**Right Hand Template:**
- QR code 1: Bottom-left corner
- QR code 2: Top-right corner

### How Validation Works
The app uses the QR codes as **reference markers** to:
1. Detect that the template is in frame (both QR codes visible)
2. Estimate camera distance (based on pixel distance between codes)
3. Verify orientation (diagonal angle matches expected layout)

## Output Files

Videos are saved to the app's Documents directory with naming convention:
```
coinstack_YYYYMMDD_HHmmss_<hand>.mp4
```

Accompanying JSON metadata files contain:
- Hand used
- Template filename
- Timestamp
- Recording duration
- Device model
- App version
- Video resolution
- Frame rate

## Building

1. Open `CoinStackCapture.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on a physical iOS device (camera required)

## Permissions

The app requests:
- **Camera**: Required for video recording
- **Photos**: Optional, for exporting to photo library

