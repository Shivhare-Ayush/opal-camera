import SwiftUI

@main
struct OpalApp: App {
    var body: some Scene {
        WindowGroup {
            CameraViewfinder()
                .preferredColorScheme(.dark)
        }
    }
}
