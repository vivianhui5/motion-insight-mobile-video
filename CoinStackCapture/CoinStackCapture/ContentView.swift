import SwiftUI

/// Root navigation container managing the app flow:
/// Landing → Hand Selection → Camera Alignment + Recording → Video Review → Save/Finish
struct ContentView: View {
    /// Tracks which screen is currently displayed
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            LandingView(onStartCapture: {
                navigationPath.append(AppScreen.handSelection)
            })
            .navigationDestination(for: AppScreen.self) { screen in
                ZStack {
                    // Always show black background to prevent white flash
                    Color.black.ignoresSafeArea()
                    
                    switch screen {
                    case .handSelection:
                        HandSelectionView(
                            onHandSelected: { hand in
                                print("📍 Hand selected: \(hand), navigating to camera...")
                                navigationPath.append(AppScreen.cameraAlignment(hand))
                            },
                            onBack: {
                                print("📍 Back from hand selection")
                                navigationPath.removeLast()
                            }
                        )
                        
                    case .cameraAlignment(let hand):
                        // Hand is passed directly through navigation
                        CameraAlignmentView(
                            selectedHand: hand,
                            onRecordingComplete: { videoURL, metadata in
                                print("📍 Recording complete, navigating to review...")
                                // Pass data directly through navigation
                                navigationPath.append(AppScreen.videoReview(videoURL, metadata))
                            },
                            onBack: {
                                print("📍 Back from camera")
                                navigationPath.removeLast()
                            }
                        )
                        
                    case .videoReview(let videoURL, let metadata):
                        // Video URL and metadata passed directly through navigation
                        VideoReviewView(
                            videoURL: videoURL,
                            onRetake: {
                                print("📍 Retaking video")
                                navigationPath.removeLast()
                            },
                            onDone: {
                                print("📍 Video approved, navigating to save...")
                                navigationPath.append(AppScreen.saveFinish(videoURL, metadata))
                            }
                        )
                        
                    case .saveFinish(let videoURL, let metadata):
                        // All data passed directly through navigation
                        SaveFinishView(
                            videoURL: videoURL,
                            metadata: metadata,
                            onBackToHome: {
                                print("📍 Back to home")
                                navigationPath = NavigationPath()
                            }
                        )
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Enumeration of app screens for navigation
/// All data is passed directly through enum cases to avoid SwiftUI state timing issues
enum AppScreen: Hashable {
    case handSelection
    case cameraAlignment(HandSelection)
    case videoReview(URL, SessionMetadata)
    case saveFinish(URL, SessionMetadata)
}

#Preview {
    ContentView()
}

