import Foundation
import XCTest
@testable import Playloom

final class BackgroundHTTPClientTests: XCTestCase {
    func testTransferMetadataRoundTripsWithoutResponseBytes() throws {
        let store = MemoryTransferStore()
        let record = BackgroundHTTPClient.TransferRecord(
            taskIdentifier: 41, requestBodyURL: URL(fileURLWithPath: "/private/body"),
            responseURL: URL(fileURLWithPath: "/private/response"), projectID: ProjectID(), runID: RunID(),
            operationID: OperationID(), candidateID: CandidateID(), baseRevisionID: BaseRevisionID(),
            state: .completed, responseStatus: 200, responseHeaders: ["Content-Type": "application/json"], errorDescription: nil)
        try store.save([record])
        let restored = try XCTUnwrap(store.load().first)
        XCTAssertEqual(restored, record)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.responseURL.path))
    }

    func testRecoveryMarksMissingBackgroundTaskInterrupted() async throws {
        let store = MemoryTransferStore()
        let record = BackgroundHTTPClient.TransferRecord(
            taskIdentifier: 99, requestBodyURL: URL(fileURLWithPath: "/private/body"),
            responseURL: URL(fileURLWithPath: "/private/response"), projectID: ProjectID(), runID: RunID(),
            operationID: OperationID(), candidateID: nil, baseRevisionID: BaseRevisionID(),
            state: .running, responseStatus: nil, responseHeaders: [:], errorDescription: nil)
        try store.save([record])
        let client = BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral))
        let metadata = try await client.recover()
        XCTAssertEqual(metadata.first?.taskIdentifier, 99)
        XCTAssertEqual(metadata.first?.state, .interrupted)
    }

    func testCompletedResponseStaysDurableUntilAcknowledged() async throws {
        let store = MemoryTransferStore()
        let bodyURL = temporaryURL("body")
        let responseURL = temporaryURL("response")
        defer {
            try? FileManager.default.removeItem(at: bodyURL)
            try? FileManager.default.removeItem(at: responseURL)
        }
        try Data("request".utf8).write(to: bodyURL)
        try Data("response".utf8).write(to: responseURL)
        let record = BackgroundHTTPClient.TransferRecord(
            taskIdentifier: 17, requestBodyURL: bodyURL, responseURL: responseURL,
            projectID: ProjectID(), runID: RunID(), operationID: OperationID(),
            candidateID: nil, baseRevisionID: BaseRevisionID(), state: .completed,
            responseStatus: 200, responseHeaders: [:], errorDescription: nil
        )
        try store.save([record])
        let client = BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral))

        let result = try await client.waitForTransfer(taskIdentifier: record.taskIdentifier)
        XCTAssertEqual(result.data, Data("response".utf8))
        XCTAssertEqual(try store.load(), [record])
        XCTAssertTrue(FileManager.default.fileExists(atPath: responseURL.path))

        try client.acknowledgeTransfer(taskIdentifier: record.taskIdentifier)
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: responseURL.path))
    }

    func testCancelledReattachedWaitMarksTransferCancelled() async throws {
        let store = MemoryTransferStore()
        let record = BackgroundHTTPClient.TransferRecord(
            taskIdentifier: 23, requestBodyURL: temporaryURL("body"), responseURL: temporaryURL("response"),
            projectID: ProjectID(), runID: RunID(), operationID: OperationID(),
            candidateID: nil, baseRevisionID: BaseRevisionID(), state: .running,
            responseStatus: nil, responseHeaders: [:], errorDescription: nil
        )
        try store.save([record])
        let client = BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral))
        let waiter = Task {
            try await client.waitForTransfer(taskIdentifier: record.taskIdentifier)
        }
        await Task.yield()
        waiter.cancel()

        do {
            _ = try await waiter.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected cancellation path.
        }
        XCTAssertEqual(client.metadata(for: record.runID).first?.state, .cancelled)
    }

    func testCancelTransfersDurablyCancelsRunningRecordsAndRetainsFilesUntilCleanup() async throws {
        let store = MemoryTransferStore()
        let record = try makeRecord(taskIdentifier: 24, runID: RunID(), state: .running)
        defer {
            try? FileManager.default.removeItem(at: record.requestBodyURL)
            try? FileManager.default.removeItem(at: record.responseURL)
        }
        try store.save([record])
        let client = BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral))

        let cancelled = try await client.cancelTransfers(for: record.runID)
        XCTAssertEqual(cancelled, [record.taskIdentifier])
        XCTAssertEqual(client.metadata(for: record.runID).first?.state, .cancelled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.requestBodyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.responseURL.path))
        XCTAssertEqual(try client.cleanupTerminalTransfers(), [record.taskIdentifier])
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.requestBodyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.responseURL.path))
    }

    func testRecreatedClientEnumeratesAndCancelsTheRetainedSessionTask() async throws {
        HangingURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = MemoryTransferStore()
        let context = GenerationRequest(
            operation: .generate,
            projectID: ProjectID(),
            runID: RunID(),
            candidateID: CandidateID(),
            operationID: OperationID(),
            baseRevisionID: BaseRevisionID(),
            prompt: "game"
        )
        let task = session.dataTask(with: URL(string: "https://playloom.test")!)
        let record = BackgroundHTTPClient.TransferRecord(
            taskIdentifier: task.taskIdentifier,
            requestBodyURL: temporaryURL("reattach-body"),
            responseURL: temporaryURL("reattach-response"),
            projectID: context.projectID,
            runID: context.runID,
            operationID: context.operationID,
            candidateID: context.candidateID,
            baseRevisionID: context.baseRevisionID,
            state: .running,
            responseStatus: nil,
            responseHeaders: [:],
            errorDescription: nil
        )
        defer {
            task.cancel()
            session.invalidateAndCancel()
        }
        try store.save([record])
        task.resume()
        for _ in 0..<100 where !HangingURLProtocol.started {
            try await ContinuousClock().sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(HangingURLProtocol.started)

        let recreatedClient = BackgroundHTTPClient(store: store, session: session)
        let cancelled = try await recreatedClient.cancelTransfers(for: context.runID)

        XCTAssertEqual(cancelled, [record.taskIdentifier])
        XCTAssertNotEqual(task.state, .suspended)
        XCTAssertEqual(try store.load().first?.state, .cancelled)
    }

    func testRecreatedClientCancelsTaskForPersistedCancellationBeforePreviousProcessStoppedIt() async throws {
        HangingURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = MemoryTransferStore()
        let context = GenerationRequest(
            operation: .generate,
            projectID: ProjectID(),
            runID: RunID(),
            candidateID: CandidateID(),
            operationID: OperationID(),
            baseRevisionID: BaseRevisionID(),
            prompt: "game"
        )
        let task = session.dataTask(with: URL(string: "https://playloom.test")!)
        let record = BackgroundHTTPClient.TransferRecord(
            taskIdentifier: task.taskIdentifier,
            requestBodyURL: temporaryURL("cancelled-reattach-body"),
            responseURL: temporaryURL("cancelled-reattach-response"),
            projectID: context.projectID,
            runID: context.runID,
            operationID: context.operationID,
            candidateID: context.candidateID,
            baseRevisionID: context.baseRevisionID,
            state: .cancelled,
            responseStatus: nil,
            responseHeaders: [:],
            errorDescription: "Cancelled"
        )
        defer {
            task.cancel()
            session.invalidateAndCancel()
        }
        try store.save([record])
        task.resume()
        for _ in 0..<100 where !HangingURLProtocol.started {
            try await ContinuousClock().sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(HangingURLProtocol.started)

        let recreatedClient = BackgroundHTTPClient(store: store, session: session)
        let cancelled = try await recreatedClient.cancelTransfers(for: context.runID)

        XCTAssertEqual(cancelled, [record.taskIdentifier])
        XCTAssertNotEqual(task.state, .running)
        XCTAssertNotEqual(task.state, .suspended)
        XCTAssertEqual(try store.load().first?.state, .cancelled)
    }

    func testRetainedTaskIsCancelledEvenWhenCancellationCheckpointCannotPersist() async throws {
        HangingURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let context = GenerationRequest(
            operation: .generate,
            projectID: ProjectID(),
            runID: RunID(),
            candidateID: CandidateID(),
            operationID: OperationID(),
            baseRevisionID: BaseRevisionID(),
            prompt: "game"
        )
        let task = session.dataTask(with: URL(string: "https://playloom.test")!)
        let record = BackgroundHTTPClient.TransferRecord(
            taskIdentifier: task.taskIdentifier,
            requestBodyURL: temporaryURL("failing-cancel-body"),
            responseURL: temporaryURL("failing-cancel-response"),
            projectID: context.projectID,
            runID: context.runID,
            operationID: context.operationID,
            candidateID: context.candidateID,
            baseRevisionID: context.baseRevisionID,
            state: .running,
            responseStatus: nil,
            responseHeaders: [:],
            errorDescription: nil
        )
        defer {
            task.cancel()
            session.invalidateAndCancel()
        }
        let store = FailingSaveTransferStore(records: [record])
        task.resume()
        for _ in 0..<100 where !HangingURLProtocol.started {
            try await ContinuousClock().sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(HangingURLProtocol.started)

        let recreatedClient = BackgroundHTTPClient(store: store, session: session)
        do {
            _ = try await recreatedClient.cancelTransfers(for: context.runID)
            XCTFail("Expected cancellation checkpoint failure")
        } catch {
            // The durable transport checkpoint failed, but the retained OS task
            // must still be cancelled before the error is reported.
        }

        XCTAssertNotEqual(task.state, .running)
        XCTAssertNotEqual(task.state, .suspended)
    }

    func testUploadFailsBeforeResumeWhenTransferMetadataCannotPersist() async throws {
        let client = BackgroundHTTPClient(store: ThrowingTransferStore(), session: URLSession(configuration: .ephemeral))
        let context = GenerationRequest(
            operation: .generate, projectID: ProjectID(), runID: RunID(),
            operationID: OperationID(), baseRevisionID: BaseRevisionID(), prompt: "game"
        )
        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        request.httpMethod = "POST"

        do {
            _ = try await client.upload(for: request, body: Data("body".utf8), context: context)
            XCTFail("Expected metadata persistence failure")
        } catch is BackgroundHTTPClient.Error {
            // The request must not be allowed to proceed without durable identity.
        }
    }

    func testTransferStoreLoadFailureDoesNotStartUnjournaledUpload() async throws {
        let store = FailingLoadTransferStore()
        let client = BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral))
        let context = GenerationRequest(
            operation: .generate, projectID: ProjectID(), runID: RunID(),
            operationID: OperationID(), baseRevisionID: BaseRevisionID(), prompt: "game"
        )
        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        request.httpMethod = "POST"

        do {
            _ = try await client.upload(for: request, body: Data("body".utf8), context: context)
            XCTFail("Expected transfer-store load failure")
        } catch is BackgroundHTTPClient.Error {
            XCTAssertFalse(store.saveCalled)
        }
    }

    func testPersistedResponseHeadersAreRecoverySafeOnly() {
        let headers: [AnyHashable: Any] = [
            "Content-Type": "application/json",
            "Content-Length": "42",
            "Retry-After": "3",
            "Authorization": "Bearer secret",
            "Cookie": "session=secret",
            "Set-Cookie": "session=secret",
            "X-Request-ID": "request-secret",
            "X-Arbitrary": "not-safe"
        ]

        let persisted = BackgroundHTTPClient.safeResponseHeaders(headers)
        XCTAssertEqual(persisted, ["content-type": "application/json", "content-length": "42", "retry-after": "3"])
    }

    func testTransferMetadataRoundTripRedactsSensitiveHeaders() throws {
        let metadata = BackgroundTransferMetadata(
            taskIdentifier: 51,
            projectID: ProjectID(),
            runID: RunID(),
            operationID: OperationID(),
            candidateID: CandidateID(),
            baseRevisionID: BaseRevisionID(),
            state: .completed,
            responseHeaders: [
                "Content-Type": "application/json",
                "Authorization": "Bearer secret",
                "Cookie": "session=secret",
                "X-Request-ID": "private-request"
            ]
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(BackgroundTransferMetadata.self, from: data)

        XCTAssertEqual(decoded.responseHeaders, ["content-type": "application/json"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).lowercased().contains("authorization"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).lowercased().contains("cookie"))
    }

    func testApplicationSupportTransferStorePersistsOnlyWhitelistedHeaders() throws {
        let fileURL = temporaryURL("headers-store")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let record = BackgroundHTTPClient.TransferRecord(
            taskIdentifier: 52,
            requestBodyURL: temporaryURL("headers-body"),
            responseURL: temporaryURL("headers-response"),
            projectID: ProjectID(),
            runID: RunID(),
            operationID: OperationID(),
            candidateID: CandidateID(),
            baseRevisionID: BaseRevisionID(),
            state: .completed,
            responseStatus: 200,
            responseHeaders: [
                "Content-Type": "application/json",
                "Authorization": "Bearer secret",
                "Set-Cookie": "session=secret"
            ],
            errorDescription: nil
        )
        let store = ApplicationSupportTransferStore(fileURL: fileURL)

        try store.save([record])
        let restored = try XCTUnwrap(store.load().first)

        XCTAssertEqual(restored.responseHeaders, ["content-type": "application/json"])
        XCTAssertFalse(String(decoding: try Data(contentsOf: fileURL), as: UTF8.self).lowercased().contains("authorization"))
        XCTAssertFalse(String(decoding: try Data(contentsOf: fileURL), as: UTF8.self).lowercased().contains("set-cookie"))
    }

    func testTerminalCleanupIsBoundedRetainsActiveRunsAndRemovesFiles() throws {
        let store = MemoryTransferStore()
        let retainedRun = RunID()
        let removableRun = RunID()
        let retained = try makeRecord(taskIdentifier: 1, runID: retainedRun, state: .completed)
        let removable = try makeRecord(taskIdentifier: 2, runID: removableRun, state: .completed)
        defer {
            try? FileManager.default.removeItem(at: retained.requestBodyURL)
            try? FileManager.default.removeItem(at: retained.responseURL)
        }
        try store.save([retained, removable])
        let client = BackgroundHTTPClient(store: store, session: URLSession(configuration: .ephemeral))

        XCTAssertEqual(try client.cleanupTerminalTransfers(retaining: [retainedRun], limit: 1), [2])
        XCTAssertEqual(client.metadata(for: retainedRun).map(\.taskIdentifier), [1])
        XCTAssertTrue(client.metadata(for: removableRun).isEmpty)
        XCTAssertTrue(try store.load().contains(retained))
        XCTAssertFalse(FileManager.default.fileExists(atPath: removable.responseURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: removable.requestBodyURL.path))
    }

    func testTerminalCleanupRemovesBoundedOrphanedTransportFiles() throws {
        let root = temporaryURL("orphan-root")
        let store = MemoryTransferStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let orphanRequest = root.appending(path: "request-orphan.json")
        let orphanResponse = root.appending(path: "response-orphan.bin")
        try Data("prompt and source".utf8).write(to: orphanRequest)
        try Data("response".utf8).write(to: orphanResponse)

        let client = BackgroundHTTPClient(
            store: store,
            session: URLSession(configuration: .ephemeral),
            transportRoot: root
        )

        XCTAssertTrue(try client.cleanupTerminalTransfers(limit: 1).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanRequest.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanResponse.path))
        XCTAssertTrue(try client.cleanupTerminalTransfers(limit: 1).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanResponse.path))
    }

    private func makeRecord(taskIdentifier: Int, runID: RunID, state: BackgroundHTTPClient.TransferState) throws -> BackgroundHTTPClient.TransferRecord {
        let bodyURL = temporaryURL("cleanup-body-\(taskIdentifier)")
        let responseURL = temporaryURL("cleanup-response-\(taskIdentifier)")
        try Data("body".utf8).write(to: bodyURL)
        try Data("response".utf8).write(to: responseURL)
        return BackgroundHTTPClient.TransferRecord(taskIdentifier: taskIdentifier, requestBodyURL: bodyURL, responseURL: responseURL, projectID: ProjectID(), runID: runID, operationID: OperationID(), candidateID: nil, baseRevisionID: BaseRevisionID(), state: state, responseStatus: 200, responseHeaders: [:], errorDescription: nil)
    }

    private func temporaryURL(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "playloom-transfer-\(label)-\(UUID().uuidString)")
    }
}

private final class MemoryTransferStore: BackgroundTransferStoring, @unchecked Sendable {
    private var records: [BackgroundHTTPClient.TransferRecord] = []
    func load() throws -> [BackgroundHTTPClient.TransferRecord] { records }
    func save(_ records: [BackgroundHTTPClient.TransferRecord]) throws { self.records = records }
}

private final class FailingSaveTransferStore: BackgroundTransferStoring, @unchecked Sendable {
    private let records: [BackgroundHTTPClient.TransferRecord]

    init(records: [BackgroundHTTPClient.TransferRecord]) {
        self.records = records
    }

    func load() throws -> [BackgroundHTTPClient.TransferRecord] { records }
    func save(_ records: [BackgroundHTTPClient.TransferRecord]) throws { throw BackgroundHTTPClient.Error.persistenceFailure }
}

private struct ThrowingTransferStore: BackgroundTransferStoring {
    func load() throws -> [BackgroundHTTPClient.TransferRecord] { [] }
    func save(_ records: [BackgroundHTTPClient.TransferRecord]) throws { throw BackgroundHTTPClient.Error.persistenceFailure }
}

private final class FailingLoadTransferStore: BackgroundTransferStoring, @unchecked Sendable {
    var saveCalled = false
    func load() throws -> [BackgroundHTTPClient.TransferRecord] { throw BackgroundHTTPClient.Error.persistenceFailure }
    func save(_ records: [BackgroundHTTPClient.TransferRecord]) throws { saveCalled = true }
}

private final class HangingURLProtocol: URLProtocol, @unchecked Sendable {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var started = false
    }

    private static let state = State()

    static var started: Bool {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.started
    }

    static func reset() {
        state.lock.lock()
        state.started = false
        state.lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.lock.lock()
        Self.state.started = true
        Self.state.lock.unlock()
    }

    override func stopLoading() {}
}
