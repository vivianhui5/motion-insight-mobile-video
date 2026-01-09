import SwiftUI

/// Root navigation container managing the app flow:
/// Landing → Hand Selection → Camera Alignment + Recording → Video Review → Save/Finish
struct ContentView: View {
    /// Tracks which screen is currently displayed
    @State private var navigationPath = NavigationPath()
    
    /// Currently selected hand for the session
    @State private var selectedHand: HandSelection?
    
    /// URL of the recorded video file
    @State private var recordedVideoURL: URL?
    
    /// Session metadata for the current recording
    @State private var sessionMetadata: SessionMetadata?
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            LandingView(onStartCapture: {
                navigationPath.append(AppScreen.handSelection)
            })
            .navigationDestination(for: AppScreen.self) { screen in
                switch screen {
                case .handSelection:
                    HandSelectionView(
                        onHandSelected: { hand in
                            selectedHand = hand
                            navigationPath.append(AppScreen.cameraAlignment)
                        },
                        onBack: {
                            navigationPath.removeLast()
                        }
                    )
                    
                case .cameraAlignment:
                    if let hand = selectedHand {
                        CameraAlignmentView(
                            selectedHand: hand,
                            onRecordingComplete: { videoURL, metadata in
                                recordedVideoURL = videoURL
                                sessionMetadata = metadata
                                navigationPath.append(AppScreen.videoReview)
                            },
                            onBack: {
                                navigationPath.removeLast()
                            }
                        )
                    }
                    
                case .videoReview:
                    if let videoURL = recordedVideoURL {
                        VideoReviewView(
                            videoURL: videoURL,
                            onRetake: {
                                // Remove review screen, go back to camera
                                navigationPath.removeLast()
                            },
                            onDone: {
                                navigationPath.append(AppScreen.saveFinish)
                            }
                        )
                    }
                    
                case .saveFinish:
                    if let videoURL = recordedVideoURL,
                       let metadata = sessionMetadata {
                        SaveFinishView(
                            videoURL: videoURL,
                            metadata: metadata,
                            onBackToHome: {
                                // Reset all state and return to landing
                                selectedHand = nil
                                recordedVideoURL = nil
                                sessionMetadata = nil
                                navigationPath = NavigationPath()
                            }
                        )
                    }
                }
            }
        }
    }
}

/// Enumeration of app screens for navigation
enum AppScreen: Hashable {
    case handSelection
    case cameraAlignment
    case videoReview
    case saveFinish
}

#Preview {
    ContentView()
}

