import Foundation

/// Runs long provider uploads in an iOS background URL session. The system may
/// suspend the UI process while the request continues and relaunch it to deliver completion.
nonisolated final class BackgroundHTTPClient: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = BackgroundHTTPClient()
    static let identifier = "dev.corismix.playloom.provider-background"

    private struct State { var data = Data(); let continuation: CheckedContinuation<(Data, URLResponse), Error>; let bodyURL: URL }
    private let lock = NSLock()
    private var states: [Int: State] = [:]
    private var backgroundCompletion: (@Sendable () -> Void)?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func upload(for request: URLRequest, body: Data) async throws -> (Data, URLResponse) {
        let bodyURL = FileManager.default.temporaryDirectory.appending(path: "playloom-provider-\(UUID().uuidString).json")
        try body.write(to: bodyURL, options: .atomic)
        return try await withCheckedThrowingContinuation { continuation in
            var request = request; request.httpBody = nil
            let task = session.uploadTask(with: request, fromFile: bodyURL)
            lock.withLock { states[task.taskIdentifier] = State(continuation: continuation, bodyURL: bodyURL) }
            task.resume()
        }
    }

    func handleEvents(completion: @escaping @Sendable () -> Void) {
        lock.withLock { backgroundCompletion = completion }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.withLock { states[dataTask.taskIdentifier]?.data.append(data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let state = lock.withLock { states.removeValue(forKey: task.taskIdentifier) }
        guard let state else { return }
        try? FileManager.default.removeItem(at: state.bodyURL)
        if let error { state.continuation.resume(throwing: error) }
        else if let response = task.response { state.continuation.resume(returning: (state.data, response)) }
        else { state.continuation.resume(throwing: URLError(.badServerResponse)) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = lock.withLock { let value = backgroundCompletion; backgroundCompletion = nil; return value }
        DispatchQueue.main.async { completion?() }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() }
}
