import SwiftUI

@main
struct LiveGradedApp: App {
    var body: some Scene {
        WindowGroup {
            CameraViewfinder()
                .preferredColorScheme(.dark)
        }
    }
}
