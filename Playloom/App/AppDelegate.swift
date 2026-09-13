import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    private(set) static var backgroundSessionWasDelivered = false

    static var launchRecoveryReason: RunRecoveryReason {
        backgroundSessionWasDelivered ? .osRelaunchInterrupted : .forceQuitUnknown
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == BackgroundHTTPClient.identifier else { completionHandler(); return }
        Self.backgroundSessionWasDelivered = true
        BackgroundHTTPClient.shared.handleEvents(completion: completionHandler)
    }
}
