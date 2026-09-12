import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == BackgroundHTTPClient.identifier else { completionHandler(); return }
        BackgroundHTTPClient.shared.handleEvents(completion: completionHandler)
    }
}
