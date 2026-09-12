import SwiftUI

@main
struct PlayloomApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            GenerationView()
        }
    }
}
