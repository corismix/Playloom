import Foundation

nonisolated protocol BackgroundTransferStoring: Sendable {
    func load() throws -> [BackgroundHTTPClient.TransferRecord]
    func save(_ records: [BackgroundHTTPClient.TransferRecord]) throws
}

nonisolated final class ApplicationSupportTransferStore: BackgroundTransferStoring, @unchecked Sendable {
    private let fileURL: URL
    init(fileURL: URL? = nil) {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Playloom/ProviderTransport", directoryHint: .isDirectory)
        self.fileURL = fileURL ?? root.appending(path: "transfers.json")
    }
    func load() throws -> [BackgroundHTTPClient.TransferRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([BackgroundHTTPClient.TransferRecord].self, from: Data(contentsOf: fileURL))
    }
    func save(_ records: [BackgroundHTTPClient.TransferRecord]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sanitized = records.map { record in
            var copy = record
            copy.responseHeaders = BackgroundTransferHeaderPolicy.sanitize(record.responseHeaders)
            return copy
        }
        try JSONEncoder().encode(sanitized).write(to: fileURL, options: .atomic)
    }
}

nonisolated final class BackgroundHTTPClient: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = BackgroundHTTPClient()
    static let identifier = "dev.corismix.playloom.provider-background"
    nonisolated enum TransferState: String, Codable, Sendable { case running, completed, failed, cancelled, interrupted }
    nonisolated struct TransferRecord: Codable, Equatable, Sendable {
        let taskIdentifier: Int; let requestBodyURL: URL; let responseURL: URL
        let projectID: ProjectID; let runID: RunID; let operationID: OperationID
        let candidateID: CandidateID?; let baseRevisionID: BaseRevisionID
        var state: TransferState; var responseStatus: Int?; var responseHeaders: [String: String]
        var errorDescription: String?; var updatedAt: Date = Date()

        init(
            taskIdentifier: Int,
            requestBodyURL: URL,
            responseURL: URL,
            projectID: ProjectID,
            runID: RunID,
            operationID: OperationID,
            candidateID: CandidateID?,
            baseRevisionID: BaseRevisionID,
            state: TransferState,
            responseStatus: Int?,
            responseHeaders: [String: String],
            errorDescription: String?,
            updatedAt: Date = Date()
        ) {
            self.taskIdentifier = taskIdentifier
            self.requestBodyURL = requestBodyURL
            self.responseURL = responseURL
            self.projectID = projectID
            self.runID = runID
            self.operationID = operationID
            self.candidateID = candidateID
            self.baseRevisionID = baseRevisionID
            self.state = state
            self.responseStatus = responseStatus
            self.responseHeaders = BackgroundTransferHeaderPolicy.sanitize(responseHeaders)
            self.errorDescription = errorDescription
            self.updatedAt = updatedAt
        }

        private enum CodingKeys: String, CodingKey {
            case taskIdentifier, requestBodyURL, responseURL, projectID, runID, operationID
            case candidateID, baseRevisionID, state, responseStatus, responseHeaders, errorDescription, updatedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                taskIdentifier: try container.decode(Int.self, forKey: .taskIdentifier),
                requestBodyURL: try container.decode(URL.self, forKey: .requestBodyURL),
                responseURL: try container.decode(URL.self, forKey: .responseURL),
                projectID: try container.decode(ProjectID.self, forKey: .projectID),
                runID: try container.decode(RunID.self, forKey: .runID),
                operationID: try container.decode(OperationID.self, forKey: .operationID),
                candidateID: try container.decodeIfPresent(CandidateID.self, forKey: .candidateID),
                baseRevisionID: try container.decode(BaseRevisionID.self, forKey: .baseRevisionID),
                state: try container.decode(TransferState.self, forKey: .state),
                responseStatus: try container.decodeIfPresent(Int.self, forKey: .responseStatus),
                responseHeaders: try container.decodeIfPresent([String: String].self, forKey: .responseHeaders) ?? [:],
                errorDescription: try container.decodeIfPresent(String.self, forKey: .errorDescription),
                updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(taskIdentifier, forKey: .taskIdentifier)
            try container.encode(requestBodyURL, forKey: .requestBodyURL)
            try container.encode(responseURL, forKey: .responseURL)
            try container.encode(projectID, forKey: .projectID)
            try container.encode(runID, forKey: .runID)
            try container.encode(operationID, forKey: .operationID)
            try container.encodeIfPresent(candidateID, forKey: .candidateID)
            try container.encode(baseRevisionID, forKey: .baseRevisionID)
            try container.encode(state, forKey: .state)
            try container.encodeIfPresent(responseStatus, forKey: .responseStatus)
            try container.encode(BackgroundTransferHeaderPolicy.sanitize(responseHeaders), forKey: .responseHeaders)
            try container.encodeIfPresent(errorDescription, forKey: .errorDescription)
            try container.encode(updatedAt, forKey: .updatedAt)
        }
    }
    nonisolated struct TransferResponse: Sendable {
        let data: Data
        let response: URLResponse
        let taskIdentifier: Int
    }
    struct TransferMetadata: Equatable, Sendable {
        let taskIdentifier: Int; let requestBodyURL: URL; let responseURL: URL
        let projectID: ProjectID; let runID: RunID; let operationID: OperationID
        let candidateID: CandidateID?; let baseRevisionID: BaseRevisionID
        let state: TransferState; let responseStatus: Int?; let responseHeaders: [String: String]
        let updatedAt: Date
    }
    enum Error: Swift.Error { case interrupted, missingResponse, persistenceFailure }

    private final class Pending: @unchecked Sendable {
        let bodyURL: URL; var continuation: CheckedContinuation<TransferResponse, Swift.Error>?; var finished = false
        init(bodyURL: URL, continuation: CheckedContinuation<TransferResponse, Swift.Error>) { self.bodyURL = bodyURL; self.continuation = continuation }
    }
    private final class CancellationBox: @unchecked Sendable { var task: URLSessionUploadTask? }
    private let store: BackgroundTransferStoring
    private let storeLoadFailed: Bool
    private let transportRoot: URL
    private let lock = NSLock(); private var records: [Int: TransferRecord]; private var pending: [Int: Pending] = [:]; private var tasks: [Int: URLSessionTask] = [:]
    private var backgroundCompletion: (() -> Void)?; private let sessionBox = SessionBox()
    private var session: URLSession {
        lock.withLock {
            if let value = sessionBox.value { return value }
            let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
            configuration.isDiscretionary = false; configuration.sessionSendsLaunchEvents = true
            configuration.timeoutIntervalForRequest = 300; configuration.timeoutIntervalForResource = 600
            let value = URLSession(configuration: configuration, delegate: self, delegateQueue: nil); sessionBox.value = value; return value
        }
    }

    init(store: BackgroundTransferStoring = ApplicationSupportTransferStore(), session: URLSession? = nil, transportRoot: URL? = nil) {
        self.store = store
        self.transportRoot = transportRoot ?? Self.defaultTransportRoot()
        let loadedRecords: [TransferRecord]
        do {
            loadedRecords = try store.load()
            self.storeLoadFailed = false
        } catch {
            loadedRecords = []
            self.storeLoadFailed = true
        }
        self.records = loadedRecords.reduce(into: [:]) { $0[$1.taskIdentifier] = $1 }
        super.init(); if let session { sessionBox.value = session }
    }

    func upload(for request: URLRequest, body: Data, context: GenerationRequest) async throws -> TransferResponse {
        try ensureStoreLoaded()
        try FileManager.default.createDirectory(at: transportRoot, withIntermediateDirectories: true)
        let bodyURL = transportRoot.appending(path: "request-\(UUID().uuidString).json")
        let responseURL = transportRoot.appending(path: "response-\(UUID().uuidString).bin")
        try body.write(to: bodyURL, options: .atomic)
        try Data().write(to: responseURL, options: .atomic)
        var request = request; request.httpBody = nil; let cancellation = CancellationBox()
        return try await withTaskCancellationHandler(operation: {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TransferResponse, Swift.Error>) in
                let task = session.uploadTask(with: request, fromFile: bodyURL); cancellation.task = task
                let record = TransferRecord(taskIdentifier: task.taskIdentifier, requestBodyURL: bodyURL, responseURL: responseURL,
                    projectID: context.projectID, runID: context.runID, operationID: context.operationID, candidateID: context.candidateID,
                    baseRevisionID: context.baseRevisionID, state: .running, responseStatus: nil, responseHeaders: [:], errorDescription: nil)
                do {
                    try lock.withLock {
                        pending[task.taskIdentifier] = Pending(bodyURL: bodyURL, continuation: continuation)
                        records[task.taskIdentifier] = record
                        tasks[task.taskIdentifier] = task
                        try persistLocked()
                    }
                    if Task.isCancelled { finishCancelled(task.taskIdentifier) } else { task.resume() }
                } catch {
                    lock.withLock {
                        pending.removeValue(forKey: task.taskIdentifier)
                        records.removeValue(forKey: task.taskIdentifier)
                        tasks.removeValue(forKey: task.taskIdentifier)
                    }
                    try? FileManager.default.removeItem(at: bodyURL)
                    try? FileManager.default.removeItem(at: responseURL)
                    task.cancel()
                    continuation.resume(throwing: Error.persistenceFailure)
                }
            }
        }, onCancel: { [weak self, weak cancellation] in
            self?.finishCancelled(cancellation?.task?.taskIdentifier)
        })
    }

    func recover() async throws -> [TransferMetadata] {
        try ensureStoreLoaded()
        let tasks = await withCheckedContinuation { continuation in session.getAllTasks { continuation.resume(returning: $0) } }
        let ids = Set(tasks.map(\.taskIdentifier))
        return try lock.withLock {
            self.tasks = Dictionary(uniqueKeysWithValues: tasks.map { ($0.taskIdentifier, $0) })
            for (id, var record) in records where record.state == .running && !ids.contains(id) {
                record.state = .interrupted; record.errorDescription = "Background task was not recoverable after relaunch"; records[id] = record
            }
            try persistLocked()
            return records.values.map(metadata).sorted { $0.taskIdentifier < $1.taskIdentifier }
        }
    }

    func recover(for runID: RunID) async throws -> [TransferMetadata] {
        try await recover().filter { $0.runID == runID }
    }

    func metadata(for runID: RunID) -> [TransferMetadata] {
        lock.withLock { records.values.filter { $0.runID == runID }.map(metadata).sorted { $0.taskIdentifier < $1.taskIdentifier } }
    }

    func metadata(for taskIdentifier: Int) -> TransferMetadata? {
        lock.withLock { records[taskIdentifier].map(metadata) }
    }

    /// Durably cancels every still-running transfer for a run. Completed
    /// responses are deliberately retained until the caller's terminal journal
    /// write triggers cleanup; they can no longer be promoted after a durable
    /// Stop request.
    @discardableResult
    func cancelTransfers(for runID: RunID) async throws -> [Int] {
        try ensureStoreLoaded()
        let sessionTasks = await allTasks()
        var tasksToCancel: [URLSessionTask] = []
        var persistenceError: Swift.Error?
        let identifiers: [Int] = lock.withLock {
            for task in sessionTasks {
                tasks[task.taskIdentifier] = task
            }
            let previous = records
            let runningIdentifiers = records.values
                .filter { $0.runID == runID && $0.state == .running }
                .map(\.taskIdentifier)
            // A previous process may have persisted `.cancelled` immediately
            // before it crashed while the corresponding URLSession task was
            // still alive. Re-enumerated tasks are the only records that need
            // another cancellation call; terminal records without a live task
            // remain terminal and are cleaned up normally.
            let liveAlreadyCancelledIdentifiers = records.values
                .filter { $0.runID == runID && $0.state == .cancelled && tasks[$0.taskIdentifier] != nil }
                .map(\.taskIdentifier)
            let identifiers = Set(runningIdentifiers + liveAlreadyCancelledIdentifiers).sorted()
            guard !identifiers.isEmpty else { return [] }
            for identifier in runningIdentifiers where records[identifier] != nil {
                records[identifier]?.state = .cancelled
                records[identifier]?.errorDescription = "Cancelled"
                records[identifier]?.updatedAt = Date()
            }
            if !runningIdentifiers.isEmpty {
                do {
                    try persistLocked()
                } catch {
                    records = previous
                    persistenceError = error
                }
            }
            for identifier in identifiers {
                if let task = tasks.removeValue(forKey: identifier) { tasksToCancel.append(task) }
                if let value = pending.removeValue(forKey: identifier), !value.finished {
                    value.finished = true
                    value.continuation?.resume(throwing: Swift.CancellationError())
                    value.continuation = nil
                }
            }
            return identifiers
        }
        tasksToCancel.forEach { $0.cancel() }
        if let persistenceError { throw persistenceError }
        return identifiers
    }

    /// Deletes a bounded number of terminal records and their retained files.
    /// Records belonging to active runs are retained even when terminal.
    @discardableResult
    func cleanupTerminalTransfers(retaining runIDs: Set<RunID> = [], limit: Int = 100) throws -> [Int] {
        guard limit > 0 else { return [] }
        return try lock.withLock {
            try ensureStoreLoaded()
            let removable = records.values
                .filter { record in
                    switch record.state {
                    case .completed, .failed, .cancelled, .interrupted: return !runIDs.contains(record.runID)
                    case .running: return false
                    }
                }
                .sorted { $0.updatedAt < $1.updatedAt }
                .prefix(limit)
            let removed = removable.map(\.taskIdentifier)
            if !removable.isEmpty {
                for record in removable {
                    records.removeValue(forKey: record.taskIdentifier)
                    tasks.removeValue(forKey: record.taskIdentifier)
                }
                do {
                    try persistLocked()
                } catch {
                    for record in removable { records[record.taskIdentifier] = record }
                    throw error
                }
                for record in removable {
                    try? FileManager.default.removeItem(at: record.requestBodyURL)
                    try? FileManager.default.removeItem(at: record.responseURL)
                }
            }
            removeOrphanedTransferFiles(limit: limit)
            return removed
        }
    }

    func waitForTransfer(taskIdentifier: Int) async throws -> TransferResponse {
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TransferResponse, Swift.Error>) in
                let registration: WaitRegistration = lock.withLock {
                    if Task.isCancelled { return .failure(Swift.CancellationError()) }
                    guard let record = records[taskIdentifier] else { return .failure(Error.interrupted) }
                    switch record.state {
                    case .running:
                        pending[taskIdentifier] = Pending(bodyURL: record.requestBodyURL, continuation: continuation)
                        return .waiting
                    case .completed:
                        do { return .ready(try completedResponse(for: record)) }
                        catch { return .failure(error) }
                    case .failed, .cancelled, .interrupted:
                        return .failure(Error.interrupted)
                    }
                }
                switch registration {
                case .waiting:
                    if Task.isCancelled { finishCancelled(taskIdentifier) }
                case .ready(let response):
                    continuation.resume(returning: response)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }, onCancel: { [weak self] in
            self?.finishCancelled(taskIdentifier)
        })
    }
    func handleEvents(completion: @escaping () -> Void) { lock.withLock { backgroundCompletion = completion } }

    /// Removes a completed transfer only after its response has been decoded and
    /// accepted by the provider. A crash before this acknowledgement leaves the
    /// body, response, and run identity available for the next launch.
    func acknowledgeTransfer(taskIdentifier: Int) throws {
        try lock.withLock {
            try ensureStoreLoaded()
            guard let record = records[taskIdentifier], record.state == .completed else { return }
            records.removeValue(forKey: taskIdentifier)
            do {
                try persistLocked()
            } catch {
                records[taskIdentifier] = record
                throw error
            }
            tasks.removeValue(forKey: taskIdentifier)
            try? FileManager.default.removeItem(at: record.requestBodyURL)
            try? FileManager.default.removeItem(at: record.responseURL)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        var writeFailed = false
        lock.withLock {
            guard let record = records[dataTask.taskIdentifier] else { return }
            let existing = (try? Data(contentsOf: record.responseURL)) ?? Data()
            var combined = existing
            combined.append(data)
            do { try combined.write(to: record.responseURL, options: .atomic) }
            catch { writeFailed = true }
        }
        if writeFailed { failTransfer(dataTask.taskIdentifier) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        lock.withLock {
            guard var record = records[task.taskIdentifier] else { return }
            if record.state == .failed || record.state == .interrupted { return }
            let cancellationWasRequested = record.state == .cancelled
            record.state = cancellationWasRequested || isCancellation(error) ? .cancelled : (error == nil ? .completed : .failed)
            record.errorDescription = error?.localizedDescription; record.updatedAt = Date()
            if let response = task.response as? HTTPURLResponse {
                record.responseStatus = response.statusCode
                record.responseHeaders = Self.safeResponseHeaders(response.allHeaderFields)
            }
            records[task.taskIdentifier] = record
            var persistenceFailed = false
            do { try persistLocked() } catch {
                persistenceFailed = true
                record.state = .failed
                record.errorDescription = "Transfer metadata could not be saved"
                records[task.taskIdentifier] = record
            }
            tasks.removeValue(forKey: task.taskIdentifier)
            guard let value = pending.removeValue(forKey: task.taskIdentifier), !value.finished else { return }
            value.finished = true
            if persistenceFailed { value.continuation?.resume(throwing: Error.persistenceFailure) }
            else if let error { value.continuation?.resume(throwing: error) }
            else if let response = task.response, let data = try? Data(contentsOf: record.responseURL) {
                value.continuation?.resume(returning: TransferResponse(data: data, response: response, taskIdentifier: task.taskIdentifier))
            } else { value.continuation?.resume(throwing: Error.missingResponse) }
            value.continuation = nil
        }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = lock.withLock { let value = backgroundCompletion; backgroundCompletion = nil; return value }
        DispatchQueue.main.async { completion?() }
    }

    private func finishCancelled(_ identifier: Int?) {
        guard let identifier else { return }
        var task: URLSessionTask?
        lock.withLock {
            guard var record = records[identifier] else { return }
            guard record.state == .running else { return }
            record.state = .cancelled
            record.errorDescription = "Cancelled"
            record.updatedAt = Date()
            records[identifier] = record
            try? persistLocked()
            task = tasks.removeValue(forKey: identifier)
            guard let value = pending.removeValue(forKey: identifier), !value.finished else { return }
            value.finished = true
            value.continuation?.resume(throwing: Swift.CancellationError())
            value.continuation = nil
        }
        task?.cancel()
    }

    private func failTransfer(_ identifier: Int, error: Swift.Error = Error.persistenceFailure) {
        var task: URLSessionTask?
        lock.withLock {
            guard var record = records[identifier] else { return }
            guard record.state == .running else { return }
            record.state = .failed
            record.errorDescription = "Transfer response could not be saved"
            record.updatedAt = Date()
            records[identifier] = record
            try? persistLocked()
            task = tasks.removeValue(forKey: identifier)
            guard let value = pending.removeValue(forKey: identifier), !value.finished else { return }
            value.finished = true
            value.continuation?.resume(throwing: error)
            value.continuation = nil
        }
        task?.cancel()
    }

    private func completedResponse(for record: TransferRecord) throws -> TransferResponse {
        guard let status = record.responseStatus, let data = try? Data(contentsOf: record.responseURL) else { throw Error.missingResponse }
        let response = HTTPURLResponse(url: URL(string: "https://playloom.invalid")!, statusCode: status, httpVersion: nil, headerFields: record.responseHeaders)!
        return TransferResponse(data: data, response: response, taskIdentifier: record.taskIdentifier)
    }
    private func metadata(_ record: TransferRecord) -> TransferMetadata {
        TransferMetadata(taskIdentifier: record.taskIdentifier, requestBodyURL: record.requestBodyURL, responseURL: record.responseURL,
            projectID: record.projectID, runID: record.runID, operationID: record.operationID, candidateID: record.candidateID,
            baseRevisionID: record.baseRevisionID, state: record.state, responseStatus: record.responseStatus,
            responseHeaders: BackgroundTransferHeaderPolicy.sanitize(record.responseHeaders), updatedAt: record.updatedAt)
    }
    private func isCancellation(_ error: Swift.Error?) -> Bool {
        if error is Swift.CancellationError { return true }
        if let urlError = error as? URLError { return urlError.code == .cancelled }
        return false
    }
    private func persistLocked() throws { try store.save(Array(records.values)) }
    private func removeOrphanedTransferFiles(limit: Int) {
        guard limit > 0,
              let files = try? FileManager.default.contentsOfDirectory(at: transportRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        let referenced = Set(records.values.flatMap { [$0.requestBodyURL.standardizedFileURL.path, $0.responseURL.standardizedFileURL.path] })
        let candidates = files.filter { url in
            let name = url.lastPathComponent
            return (name.hasPrefix("request-") && name.hasSuffix(".json") || name.hasPrefix("response-") && name.hasSuffix(".bin"))
                && !referenced.contains(url.standardizedFileURL.path)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in candidates.prefix(limit) {
            try? FileManager.default.removeItem(at: file)
        }
    }
    private func allTasks() async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
    }
    private func ensureStoreLoaded() throws {
        if storeLoadFailed { throw Error.persistenceFailure }
    }

    static func safeResponseHeaders(_ headers: [AnyHashable: Any]) -> [String: String] {
        BackgroundTransferHeaderPolicy.sanitize(headers)
    }

    private static func defaultTransportRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Playloom/ProviderTransport", directoryHint: .isDirectory)
    }
}

private final class SessionBox: @unchecked Sendable { var value: URLSession? }
private enum WaitRegistration {
    case waiting
    case ready(BackgroundHTTPClient.TransferResponse)
    case failure(Swift.Error)
}
private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T { lock(); defer { unlock() }; return try body() }
}
