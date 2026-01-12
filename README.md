# Motion Insight — Coin Stack Capture

A native iOS app for standardized video data collection of patients performing a coin stacking task for medical screening, clinical review, and machine learning applications.

<p align="center">
  <img src="https://img.shields.io/badge/iOS-16.0+-blue?logo=apple" alt="iOS 16+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/SwiftUI-4.0-purple" alt="SwiftUI">
  <img src="https://img.shields.io/badge/AVFoundation-Video-green" alt="AVFoundation">
</p>

---

## Overview

Coin Stack Capture enables consistent, high-quality video recordings of patients performing a coin stacking motor task. The app uses QR code markers on a physical paper template to:

- **Validate positioning** — Ensure the camera is at the correct distance
- **Check orientation** — Verify the phone's angle relative to the paper
- **Provide real-time feedback** — Guide users to optimal recording conditions
- **Export standardized data** — Save videos with JSON metadata for ML pipelines

---

## Features

| Feature | Description |
|---------|-------------|
| **QR Code Detection** | Real-time Vision framework detection with overlay highlighting |
| **Distance Estimation** | Calculates camera distance from QR code pixel spacing |
| **Orientation Validation** | Ensures proper paper alignment and phone angle |
| **Motion Sensing** | Uses CoreMotion to detect phone tilt and viewing angle |
| **1080p @ 30fps Recording** | High-quality video capture with AVFoundation |
| **Video Review** | Playback with scrubbing before saving |
| **Photos Export** | Automatic save to device photo library |
| **JSON Metadata** | Structured data for ML pipeline ingestion |

---

## Requirements

- **iOS 16.0+**
- **iPhone with rear camera** (iPad not officially supported)
- **Xcode 15.0+** (for building)
- **Physical device** (camera required, simulator won't work)

---

## Quick Start

### 1. Clone & Open

```bash
git clone <repository-url>
cd motion-insight-mobile-video
open CoinStackCapture/CoinStackCapture.xcodeproj
```

### 2. Configure Signing

1. Select the project in Xcode's navigator
2. Go to **Signing & Capabilities**
3. Select your development team

### 3. Print a Template

Print one of the templates from the `templates/` folder:
- `lefthand_sheet.pdf` — For left-hand stacking
- `righthand_sheet.pdf` — For right-hand stacking

### 4. Build & Run

1. Connect your iPhone
2. Select your device as the build target
3. Press **⌘R** to build and run

---

## App Flow

```
┌─────────────┐     ┌─────────────────┐     ┌──────────────────────┐
│   Landing   │ ──▶ │  Hand Selection │ ──▶ │  Camera + Recording  │
│   Screen    │     │   (Left/Right)  │     │   (QR Alignment)     │
└─────────────┘     └─────────────────┘     └──────────┬───────────┘
                                                       │
                                                       ▼
                    ┌─────────────────┐     ┌──────────────────────┐
                    │   Save/Finish   │ ◀── │    Video Review      │
                    │     Screen      │     │    (Playback)        │
                    └─────────────────┘     └──────────────────────┘
```

### Screen Details

| Screen | Purpose |
|--------|---------|
| **Landing** | Introduction with animated coin stack and setup instructions |
| **Hand Selection** | Choose left or right hand template |
| **Camera Alignment** | Live preview with QR detection, distance/angle feedback, and recording controls |
| **Video Review** | Playback with scrubber, play/pause, retake or approve |
| **Save/Finish** | Confirmation and automatic save to Photos |

---

## Physical Setup

### Camera Positioning

For optimal recordings:

```
        Phone (horizontal)
            📱
             \  
              \  ~30° angle
               \
                ▼
    ┌──────────────────────┐
    │  QR          Coins   │   Paper template
    │                 🪙    │   (flat on desk)
    │              QR      │
    └──────────────────────┘
    
    Distance: ~50-100cm from paper
    Position: Not directly above (bird's eye)
```

### Alignment Indicators

| Indicator | Meaning |
|-----------|---------|
| 🟢 Green | Ready to record |
| 🟡 Yellow | Adjusting — follow guidance |
| ⚪ Gray | Searching for QR codes |

### Feedback Messages

- **"Position both QR codes in frame"** — Move to see both corners
- **"Move closer"** / **"Move farther"** — Adjust distance
- **"Paper is too tilted"** — Align paper flatter
- **"Angle your phone properly"** — Don't point straight down
- **"Perfect — Ready to record"** — All checks passed

---

## Template Specifications

### Paper & Printing

| Spec | Value |
|------|-------|
| Paper Size | Letter (8.5" × 11") or A4 |
| Orientation | Landscape |
| Print Scale | 100% (no scaling) |

### QR Code Details

| Spec | Value |
|------|-------|
| QR Size | 6.0 cm × 6.0 cm |
| Version | V2 |
| Error Correction | H (High) |
| Center Distance | 22.5 cm (diagonal) |

### Template Variants

**Left Hand Template:**
- QR code 1: Top-left corner
- QR code 2: Bottom-right corner
- Expected diagonal: ~45° from horizontal

**Right Hand Template:**
- QR code 1: Bottom-left corner
- QR code 2: Top-right corner
- Expected diagonal: ~-45° from horizontal

---

## Project Structure

```
motion-insight-mobile-video/
├── README.md                      # This file
├── specs.txt                      # Original specification
├── templates/                     # Printable templates
│   ├── lefthand_sheet.pdf
│   └── righthand_sheet.pdf
│
└── CoinStackCapture/              # Xcode project
    ├── CoinStackCapture.xcodeproj
    └── CoinStackCapture/
        ├── CoinStackCaptureApp.swift    # App entry point
        ├── ContentView.swift            # Root navigation
        ├── Info.plist                   # App configuration
        │
        ├── Views/
        │   ├── LandingView.swift        # Welcome screen
        │   ├── HandSelectionView.swift  # Left/right selection
        │   ├── CameraAlignmentView.swift# Recording screen
        │   ├── CameraPreviewView.swift  # AVFoundation preview
        │   ├── VideoReviewView.swift    # Playback review
        │   ├── VideoPlayerView.swift    # Player component
        │   └── SaveFinishView.swift     # Save confirmation
        │
        ├── Camera/
        │   ├── CameraManager.swift      # Session + QR detection
        │   ├── QRCodeValidator.swift    # Validation logic
        │   └── VideoRecorder.swift      # Recording utilities
        │
        ├── Models/
        │   ├── AlignmentState.swift     # Alignment status
        │   ├── SessionMetadata.swift    # Recording metadata
        │   ├── TemplateConfiguration.swift # Constants
        │   └── StorageManager.swift     # File management
        │
        ├── Resources/
        │   ├── left-template.pdf
        │   └── right-template.pdf
        │
        └── Assets.xcassets/             # Colors & icons
```

---

## Output Files

### Video Files

```
coinstack_YYYYMMDD_HHmmss_<hand>.mp4
```

- **Format:** MP4 (H.264)
- **Resolution:** 1920 × 1080 (1080p)
- **Frame Rate:** 30 fps
- **Location:** Photos Library

### Metadata Files

```json
{
  "hand": "left",
  "templateFilename": "left-template.pdf",
  "timestamp": "2026-01-12T14:30:00Z",
  "duration": 15.5,
  "deviceModel": "iPhone 14 Pro",
  "appVersion": "1.0.0",
  "resolution": "1920x1080",
  "frameRate": 30
}
```

---

## Permissions

| Permission | Required | Purpose |
|------------|----------|---------|
| **Camera** | ✅ Yes | Video recording |
| **Photos** | ✅ Yes | Save to library |
| **Motion** | Optional | Device angle detection |

The app will prompt for permissions on first use.

---

## Troubleshooting

### "No QR codes detected"

- Ensure both QR codes are fully visible in frame
- Check lighting — avoid glare on the paper
- Move closer if QR codes appear too small

### "Indicator stays yellow"

- Adjust distance (watch the distance meter)
- Keep paper relatively flat
- Don't point phone straight down

### "Recording button disabled"

Recording is now allowed even when alignment isn't perfect. If the button appears disabled, check that:
- Camera permission is granted
- Camera preview is active (not black screen)

### Black screen on camera

- Close and reopen the app
- Check camera permissions in Settings
- Ensure no other app is using the camera

---

## Technical Notes

### Frameworks Used

- **SwiftUI** — User interface
- **AVFoundation** — Camera capture and video recording
- **Vision** — QR code detection (`VNDetectBarcodesRequest`)
- **CoreMotion** — Device orientation and pitch angle
- **Photos** — Library export

### Coordinate Systems

The app handles multiple coordinate systems:
- **Vision:** Bottom-left origin, normalized (0-1)
- **UIKit:** Top-left origin, pixel coordinates
- **Camera:** Video orientation vs device orientation

QR bounding boxes are converted using `AVCaptureVideoPreviewLayer.layerRectConverted(fromMetadataOutputRect:)`.

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## License

This project is proprietary software for medical data collection.

---

## Contact

For questions or support, contact the Motion Insight team.

